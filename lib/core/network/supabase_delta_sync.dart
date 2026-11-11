import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'delta_sync.dart';

enum SyncPhase {
  notConfigured,
  needsAuthentication,
  accountMismatch,
  syncing,
  synchronized,
  offline,
}

/// Keeps SQLite authoritative while exchanging newer rows with the signed-in
/// user's Supabase account. Conflicts use last-write-wins by `updated_at`.
class SupabaseDeltaSync extends ChangeNotifier
    with WidgetsBindingObserver
    implements DeltaSync {
  static const _pageSize = 500;

  SupabaseDeltaSync(this._database, this._client, {Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final AppDatabase _database;
  final SupabaseClient? _client;
  final Connectivity _connectivity;
  SyncPhase _phase = SyncPhase.notConfigured;
  Timer? _retryTimer;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _networkAvailable = true;
  bool _running = false;

  SyncPhase get phase => _phase;
  User? get currentUser => _client?.auth.currentUser;
  bool get isConfigured => _client != null;
  bool get isOffline => !_networkAvailable || _phase == SyncPhase.offline;

  void start() {
    final client = _client;
    if (client == null) return;
    WidgetsBinding.instance.addObserver(this);
    _authSubscription ??= client.auth.onAuthStateChange.listen((event) {
      if (event.session == null) {
        _setPhase(SyncPhase.needsAuthentication);
      } else {
        unawaited(_refreshConnectivity());
      }
    });
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen(
      _handleConnectivity,
      onError: (Object _) => unawaited(synchronize()),
    );
    _retryTimer ??= Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(_refreshConnectivity()),
    );
    _setPhase(
      client.auth.currentSession == null
          ? SyncPhase.needsAuthentication
          : SyncPhase.offline,
    );
    unawaited(_refreshConnectivity());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshConnectivity());
    }
  }

  Future<void> _refreshConnectivity() async {
    try {
      _handleConnectivity(await _connectivity.checkConnectivity());
    } on Object {
      // Connectivity is advisory; the request itself decides whether it works.
      _networkAvailable = true;
      await synchronize();
    }
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    final connected = results.any(
      (result) => result != ConnectivityResult.none,
    );
    _networkAvailable = connected;
    if (!connected) {
      _setPhase(
        currentUser == null ? SyncPhase.needsAuthentication : SyncPhase.offline,
      );
      return;
    }
    if (currentUser == null) {
      _setPhase(SyncPhase.needsAuthentication);
      return;
    }
    unawaited(synchronize());
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final client = _client;
    if (client == null) throw StateError('Supabase no está configurado.');
    if (!_networkAvailable) {
      throw StateError(
        'No hay conexión. Puedes seguir trabajando localmente e iniciar sesión cuando vuelva la señal.',
      );
    }
    return client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp(String email, String password) async {
    final client = _client;
    if (client == null) throw StateError('Supabase no está configurado.');
    if (!_networkAvailable) {
      throw StateError(
        'No hay conexión. Puedes seguir trabajando localmente y crear la cuenta cuando vuelva la señal.',
      );
    }
    return client.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    await client.auth.signOut();
    _setPhase(SyncPhase.needsAuthentication);
  }

  @override
  Future<void> synchronize() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null) {
      _setPhase(SyncPhase.notConfigured);
      return;
    }
    if (user == null) {
      _setPhase(SyncPhase.needsAuthentication);
      return;
    }
    if (!_networkAvailable) {
      _setPhase(SyncPhase.offline);
      return;
    }
    if (_running) return;
    _running = true;
    _setPhase(SyncPhase.syncing);
    try {
      if (!await _isBoundTo(user.id)) {
        _setPhase(SyncPhase.accountMismatch);
        return;
      }
      await _syncClients(client, user.id);
      await _syncCapitalGroups(client, user.id);
      await _syncCards(client, user.id);
      await _syncPayments(client, user.id);
      _setPhase(SyncPhase.synchronized);
    } on Object {
      // Offline, RLS denial, or a missing server migration all leave SQLite
      // usable; retry on the next periodic tick or explicit user request.
      _setPhase(SyncPhase.offline);
    } finally {
      _running = false;
    }
  }

  Future<bool> _isBoundTo(String userId) async {
    const ownerPrefix = 'supabase_owner:';
    final owners = await (_database.select(
      _database.syncMetadata,
    )..where((row) => row.key.like('$ownerPrefix%'))).get();
    final accountKey = '$ownerPrefix$userId';
    if (owners.isNotEmpty) {
      return owners.any((row) => row.key == accountKey);
    }
    await _database
        .into(_database.syncMetadata)
        .insert(SyncMetadataCompanion.insert(key: accountKey));
    return true;
  }

  Future<void> _syncClients(SupabaseClient client, String userId) async {
    final localRows = await _database.select(_database.clientsTable).get();
    final phoneRows = await _database.select(_database.clientPhones).get();
    phoneRows.sort((first, second) {
      final clientOrder = first.clientId.compareTo(second.clientId);
      return clientOrder != 0
          ? clientOrder
          : first.position.compareTo(second.position);
    });
    final phonesByClient = <String, List<String>>{};
    for (final phone in phoneRows) {
      phonesByClient
          .putIfAbsent(phone.clientId, () => [])
          .add(phone.phoneNumber);
    }
    final cloudRows = await _selectAll(client, 'clients');
    final cloudById = {for (final row in cloudRows) row['id'] as String: row};
    final localById = {for (final row in localRows) row.id: row};
    final toPush = <Map<String, Object?>>[];

    for (final local in localRows) {
      final cloud = cloudById[local.id];
      if (cloud == null ||
          local.updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        toPush.add(
          _clientToJson(local, userId, phonesByClient[local.id] ?? const []),
        );
      }
    }
    for (final cloud in cloudRows) {
      final local = localById[cloud['id'] as String];
      if (local == null ||
          _readDate(cloud['updated_at']).isAfter(local.updatedAt)) {
        await _applyClient(cloud, local);
      }
    }
    if (toPush.isNotEmpty) {
      await _upsertInBatches(client, 'clients', toPush, 'id');
    }
  }

  Map<String, Object?> _clientToJson(
    ClientRow row,
    String userId,
    List<String> phones,
  ) => {
    'id': row.id,
    'user_id': userId,
    'full_name': row.fullName,
    'address': row.address,
    'phones': phones,
    'dpi': row.dpi,
    'dpi_folder': row.dpiFolder,
    'alias': row.alias,
    'latitude': row.latitude,
    'longitude': row.longitude,
    'created_at': row.createdAt.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
    'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
  };

  Future<void> _applyClient(
    Map<String, dynamic> cloud,
    ClientRow? existing,
  ) async {
    final phones = List<String>.from(cloud['phones'] as List? ?? const []);
    await _database.transaction(() async {
      await _database
          .into(_database.clientsTable)
          .insertOnConflictUpdate(
            ClientsTableCompanion.insert(
              id: cloud['id'] as String,
              fullName: cloud['full_name'] as String,
              address: cloud['address'] as String,
              dpi: Value(cloud['dpi'] as String?),
              dpiFolder: Value(cloud['dpi_folder'] as String?),
              alias: Value(cloud['alias'] as String?),
              photoPath: Value(existing?.photoPath),
              latitude: Value((cloud['latitude'] as num?)?.toDouble()),
              longitude: Value((cloud['longitude'] as num?)?.toDouble()),
              createdAt: _readDate(cloud['created_at']),
              updatedAt: _readDate(cloud['updated_at']),
              deletedAt: Value(_readNullableDate(cloud['deleted_at'])),
            ),
          );
      await (_database.delete(
        _database.clientPhones,
      )..where((row) => row.clientId.equals(cloud['id'] as String))).go();
      await _database.batch((batch) {
        batch.insertAll(_database.clientPhones, [
          for (var index = 0; index < phones.length; index++)
            ClientPhonesCompanion.insert(
              clientId: cloud['id'] as String,
              phoneNumber: phones[index],
              position: Value(index),
            ),
        ]);
      });
    });
  }

  Future<void> _syncCapitalGroups(SupabaseClient client, String userId) async {
    final localRows = await _database.select(_database.capitalGroups).get();
    final cloudRows = await _selectAll(client, 'capital_groups');
    final cloudById = {
      for (final row in cloudRows) row['sync_id'] as String: row,
    };
    final localById = {for (final row in localRows) row.syncId: row};
    final toPush = <Map<String, Object?>>[];
    for (final local in localRows) {
      final cloud = cloudById[local.syncId];
      if (cloud == null ||
          local.updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        toPush.add(_groupToJson(local, userId));
      }
    }
    for (final cloud in cloudRows) {
      final local = localById[cloud['sync_id'] as String];
      if (local == null ||
          _readDate(cloud['updated_at']).isAfter(local.updatedAt)) {
        await _applyGroup(cloud, local);
      }
    }
    if (toPush.isNotEmpty) {
      await _upsertInBatches(client, 'capital_groups', toPush, 'sync_id');
    }
  }

  Map<String, Object?> _groupToJson(CapitalGroupRow row, String userId) => {
    'sync_id': row.syncId,
    'user_id': userId,
    'name': row.name,
    'description': row.description,
    'created_at': row.createdAt.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
    'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
  };

  Future<void> _applyGroup(
    Map<String, dynamic> cloud,
    CapitalGroupRow? existing,
  ) async {
    final syncId = cloud['sync_id'] as String;
    final fields = CapitalGroupsCompanion(
      syncId: Value(syncId),
      name: Value(cloud['name'] as String),
      description: Value(cloud['description'] as String?),
      createdAt: Value(_readDate(cloud['created_at'])),
      updatedAt: Value(_readDate(cloud['updated_at'])),
      deletedAt: Value(_readNullableDate(cloud['deleted_at'])),
    );
    if (existing == null) {
      await _database
          .into(_database.capitalGroups)
          .insert(
            CapitalGroupsCompanion.insert(
              syncId: Value(syncId),
              name: cloud['name'] as String,
              description: Value(cloud['description'] as String?),
              createdAt: _readDate(cloud['created_at']),
              updatedAt: Value(_readDate(cloud['updated_at'])),
              deletedAt: Value(_readNullableDate(cloud['deleted_at'])),
            ),
          );
    } else {
      await (_database.update(
        _database.capitalGroups,
      )..where((row) => row.id.equals(existing.id))).write(fields);
    }
    if (_readNullableDate(cloud['deleted_at']) != null && existing != null) {
      await (_database.update(
        _database.cardsTable,
      )..where((row) => row.folderId.equals(existing.id))).write(
        CardsTableCompanion(
          folderId: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<Map<String, int>> _groupIdsBySyncId() async {
    final rows = await (_database.select(
      _database.capitalGroups,
    )..where((row) => row.deletedAt.isNull())).get();
    return {for (final row in rows) row.syncId: row.id};
  }

  Future<void> _syncCards(SupabaseClient client, String userId) async {
    final localRows = await _database.select(_database.cardsTable).get();
    final cloudRows = await _selectAll(client, 'cards');
    final cloudById = {for (final row in cloudRows) row['id'] as String: row};
    final localById = {for (final row in localRows) row.id: row};
    final groupIds = await _groupIdsBySyncId();
    final groupSyncIds = {
      for (final entry in groupIds.entries) entry.value: entry.key,
    };
    final toPush = <Map<String, Object?>>[];
    for (final local in localRows) {
      final cloud = cloudById[local.id];
      if (cloud == null ||
          local.updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        toPush.add({
          'id': local.id,
          'user_id': userId,
          'client_id': local.clientId,
          'capital_group_id': local.folderId == null
              ? null
              : groupSyncIds[local.folderId],
          'requested_amount': local.requestedAmount,
          'delivered_amount': local.deliveredAmount,
          'total_installments': local.totalInstallments,
          'weekly_amount': local.weeklyAmount,
          'status': local.status,
          'color_hex': local.colorHex,
          'start_date': local.startDate.toUtc().toIso8601String(),
          'created_at': local.createdAt.toUtc().toIso8601String(),
          'updated_at': local.updatedAt.toUtc().toIso8601String(),
        });
      }
    }
    for (final cloud in cloudRows) {
      final local = localById[cloud['id'] as String];
      if (local == null ||
          _readDate(cloud['updated_at']).isAfter(local.updatedAt)) {
        final groupSyncId = cloud['capital_group_id'] as String?;
        await _database
            .into(_database.cardsTable)
            .insertOnConflictUpdate(
              CardsTableCompanion.insert(
                id: cloud['id'] as String,
                clientId: cloud['client_id'] as String,
                folderId: Value(
                  groupSyncId == null ? null : groupIds[groupSyncId],
                ),
                requestedAmount: (cloud['requested_amount'] as num).toDouble(),
                deliveredAmount: (cloud['delivered_amount'] as num).toDouble(),
                totalInstallments: (cloud['total_installments'] as num).toInt(),
                weeklyAmount: (cloud['weekly_amount'] as num).toDouble(),
                status: Value(cloud['status'] as String),
                colorHex: Value(cloud['color_hex'] as String),
                startDate: _readDate(cloud['start_date']),
                createdAt: _readDate(cloud['created_at']),
                updatedAt: Value(_readDate(cloud['updated_at'])),
              ),
            );
      }
    }
    if (toPush.isNotEmpty) {
      await _upsertInBatches(client, 'cards', toPush, 'id');
    }
  }

  Future<void> _syncPayments(SupabaseClient client, String userId) async {
    final localRows = await _database.select(_database.payments).get();
    final cloudRows = await _selectAll(client, 'payments');
    final cloudById = {for (final row in cloudRows) row['id'] as String: row};
    final localById = {for (final row in localRows) row.id: row};
    final toPush = <Map<String, Object?>>[];
    for (final local in localRows) {
      final cloud = cloudById[local.id];
      if (cloud == null ||
          local.updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        toPush.add({
          'id': local.id,
          'user_id': userId,
          'card_id': local.cardId,
          'scheduled_date': local.scheduledDate?.toUtc().toIso8601String(),
          'amount_paid': local.amountPaid,
          'mora_cents': local.moraCents,
          'balance_after': local.balanceAfter,
          'payment_type': local.paymentType,
          'receipt_number': local.receiptNumber,
          'is_renewal': local.isRenewal,
          'created_at': local.createdAt?.toUtc().toIso8601String(),
          'created_at_estimated': local.createdAtEstimated,
          'is_manual': local.isManual,
          'position': local.position,
          'updated_at': local.updatedAt.toUtc().toIso8601String(),
          'deleted_at': local.deletedAt?.toUtc().toIso8601String(),
        });
      }
    }
    for (final cloud in cloudRows) {
      final local = localById[cloud['id'] as String];
      if (local == null ||
          _readDate(cloud['updated_at']).isAfter(local.updatedAt)) {
        await _database
            .into(_database.payments)
            .insertOnConflictUpdate(
              PaymentsCompanion.insert(
                id: cloud['id'] as String,
                cardId: Value(cloud['card_id'] as String),
                scheduledDate: Value(
                  _readNullableDate(cloud['scheduled_date']),
                ),
                amountPaid: Value((cloud['amount_paid'] as num).toDouble()),
                moraCents: Value((cloud['mora_cents'] as num).toInt()),
                balanceAfter: (cloud['balance_after'] as num).toDouble(),
                paymentType: Value(cloud['payment_type'] as String),
                receiptNumber: Value(cloud['receipt_number'] as String?),
                isRenewal: Value(cloud['is_renewal'] as bool),
                createdAt: Value(_readNullableDate(cloud['created_at'])),
                createdAtEstimated: Value(
                  cloud['created_at_estimated'] as bool,
                ),
                isManual: Value(cloud['is_manual'] as bool),
                position: Value((cloud['position'] as num).toInt()),
                updatedAt: Value(_readDate(cloud['updated_at'])),
                deletedAt: Value(_readNullableDate(cloud['deleted_at'])),
              ),
            );
      }
    }
    if (toPush.isNotEmpty) {
      await _upsertInBatches(client, 'payments', toPush, 'id');
    }
  }

  Future<List<Map<String, dynamic>>> _selectAll(
    SupabaseClient client,
    String table,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += _pageSize) {
      final page = await client
          .from(table)
          .select()
          .range(offset, offset + _pageSize - 1);
      rows.addAll(page);
      if (page.length < _pageSize) return rows;
    }
  }

  Future<void> _upsertInBatches(
    SupabaseClient client,
    String table,
    List<Map<String, Object?>> rows,
    String conflictColumn,
  ) async {
    for (var offset = 0; offset < rows.length; offset += _pageSize) {
      final end = (offset + _pageSize).clamp(0, rows.length);
      await client
          .from(table)
          .upsert(rows.sublist(offset, end), onConflict: conflictColumn);
    }
  }

  DateTime _readDate(Object? value) =>
      DateTime.parse(value as String).toLocal();

  DateTime? _readNullableDate(Object? value) =>
      value == null ? null : _readDate(value);

  void _setPhase(SyncPhase next) {
    if (_phase == next) return;
    _phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }
}
