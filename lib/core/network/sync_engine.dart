import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../features/clientes/data/services/client_photo_storage.dart';
import '../../features/cobros_tarjetas/data/datasources/local/mora_local_data_source.dart';
import '../../features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import '../database/app_database.dart';
import 'sync_remote.dart';

/// One full exchange between the local SQLite database and the account's
/// cloud copy, so a collector's tablet and backup phone converge.
///
/// Editable records use last-write-wins on `updated_at`. Records that both
/// devices may create independently use deterministic keys and merge rules
/// that cannot lose data:
/// * mora days are keyed `card_id:YYYY-MM-DD`, so both devices accrue the
///   same rows, and whether a day is paid is derived from its applications;
/// * mora applications, payment changes and notifications are append-only,
///   and their flags (`reversed`, `is_read`) only move from false to true;
/// * mora tracking keeps the earliest checkpoint and re-accrues the gap.
class SyncEngine {
  SyncEngine(
    this._db,
    this._remote,
    this._userId, {
    ClientPhotoStorage? photos,
    DateTime Function()? clock,
  }) : _photos = photos ?? ClientPhotoStorage(),
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final SyncRemote _remote;
  final String _userId;
  final ClientPhotoStorage _photos;
  final DateTime Function() _clock;

  /// Cloud `pagado` per mora sync id, kept current as rows are pushed.
  final Map<String, bool> _cloudMoraPaid = {};

  Future<void> run() async {
    await _syncClients();
    await _syncCapitalGroups();
    await _syncCards();
    await _syncPayments();
    await _syncNotifications();
    await _syncMoraDays();
    await _syncMoraApplications();
    await _reconcileMoraPaid();
    await _syncMoraTracking();
    await _syncPaymentChanges();
    await _syncCreditPlans();
    await _syncEnterpriseConfig();
  }

  // ---------------------------------------------------------------- clients

  /// Cloud marker for "photo removed on purpose". `null` means unknown
  /// (e.g. written by an app version without photo sync) and keeps the
  /// local photo.
  static const _noPhoto = '';

  String? _photoObject(String? path) =>
      path == null ? null : '$_userId/${p.basename(path)}';

  Future<void> _syncClients() async {
    final localRows = await _db.select(_db.clientsTable).get();
    final phoneRows = await _db.select(_db.clientPhones).get();
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
    final cloudRows = await _remote.selectAll('clients');
    final cloudById = {for (final row in cloudRows) row['id'] as String: row};
    final localById = {for (final row in localRows) row.id: row};
    final toPush = <Map<String, Object?>>[];

    for (final local in localRows) {
      final cloud = cloudById[local.id];
      if (cloud == null ||
          local.updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        String? photoObject = _photoObject(local.photoPath) ?? _noPhoto;
        if (photoObject != _noPhoto) {
          final file = File(local.photoPath!);
          if (await file.exists()) {
            if (cloud?['photo_object'] != photoObject) {
              await _remote.uploadPhoto(photoObject, await file.readAsBytes());
            }
          } else {
            // The file is gone locally; keep whatever the cloud already has.
            photoObject = cloud?['photo_object'] as String?;
          }
        }
        final json = _clientToJson(
          local,
          phonesByClient[local.id] ?? const [],
          photoObject,
        );
        toPush.add(json);
        cloudById[local.id] = json;
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
      await _remote.upsert('clients', toPush, 'id');
    }
    await _syncClientPhotos(cloudById.values);
  }

  Map<String, Object?> _clientToJson(
    ClientRow row,
    List<String> phones,
    String? photoObject,
  ) => {
    'id': row.id,
    'user_id': _userId,
    'full_name': row.fullName,
    'address': row.address,
    'phones': phones,
    'dpi': row.dpi,
    'dpi_folder': row.dpiFolder,
    'alias': row.alias,
    'photo_object': photoObject,
    'latitude': row.latitude,
    'longitude': row.longitude,
    'created_at': _writeDate(row.createdAt),
    'updated_at': _writeDate(row.updatedAt),
    'deleted_at': _writeNullableDate(row.deletedAt),
  };

  Future<void> _applyClient(
    Map<String, dynamic> cloud,
    ClientRow? existing,
  ) async {
    final phones = List<String>.from(cloud['phones'] as List? ?? const []);
    // A newer cloud row marked without a photo means it was removed there.
    // A different photo is fetched afterwards by _syncClientPhotos.
    final removePhoto =
        cloud['photo_object'] == _noPhoto && existing?.photoPath != null;
    await _db.transaction(() async {
      await _db
          .into(_db.clientsTable)
          .insertOnConflictUpdate(
            ClientsTableCompanion.insert(
              id: cloud['id'] as String,
              fullName: cloud['full_name'] as String,
              address: cloud['address'] as String,
              dpi: Value(cloud['dpi'] as String?),
              dpiFolder: Value(cloud['dpi_folder'] as String?),
              alias: Value(cloud['alias'] as String?),
              photoPath: Value(removePhoto ? null : existing?.photoPath),
              latitude: Value((cloud['latitude'] as num?)?.toDouble()),
              longitude: Value((cloud['longitude'] as num?)?.toDouble()),
              createdAt: _readDate(cloud['created_at']),
              updatedAt: _readDate(cloud['updated_at']),
              deletedAt: Value(_readNullableDate(cloud['deleted_at'])),
            ),
          );
      await (_db.delete(
        _db.clientPhones,
      )..where((row) => row.clientId.equals(cloud['id'] as String))).go();
      await _db.batch((batch) {
        batch.insertAll(_db.clientPhones, [
          for (var index = 0; index < phones.length; index++)
            ClientPhonesCompanion.insert(
              clientId: cloud['id'] as String,
              phoneNumber: phones[index],
              position: Value(index),
            ),
        ]);
      });
    });
    if (removePhoto) await _photos.delete(existing!.photoPath!);
  }

  /// Downloads photos this device lacks. Failures are retried next sync
  /// rather than blocking the financial data behind them.
  Future<void> _syncClientPhotos(
    Iterable<Map<String, dynamic>> cloudClients,
  ) async {
    final localById = {
      for (final row in await _db.select(_db.clientsTable).get()) row.id: row,
    };
    for (final cloud in cloudClients) {
      final object = cloud['photo_object'] as String?;
      final local = localById[cloud['id'] as String];
      if (object == null ||
          object == _noPhoto ||
          local == null ||
          local.deletedAt != null) {
        continue;
      }
      if (_photoObject(local.photoPath) == object &&
          await File(local.photoPath!).exists()) {
        continue;
      }
      try {
        final bytes = await _remote.downloadPhoto(object);
        final path = await _photos.storeBytes(bytes, p.basename(object));
        await (_db.update(_db.clientsTable)
              ..where((row) => row.id.equals(local.id)))
            .write(ClientsTableCompanion(photoPath: Value(path)));
        final previous = local.photoPath;
        if (previous != null && previous != path) {
          await _photos.delete(previous);
        }
      } on Object {
        continue;
      }
    }
  }

  // ---------------------------------------------------------- capital groups

  Future<void> _syncCapitalGroups() async {
    final localRows = await _db.select(_db.capitalGroups).get();
    final cloudRows = await _remote.selectAll('capital_groups');
    final cloudById = {
      for (final row in cloudRows) row['sync_id'] as String: row,
    };
    final localById = {for (final row in localRows) row.syncId: row};
    final toPush = <Map<String, Object?>>[];
    for (final local in localRows) {
      final cloud = cloudById[local.syncId];
      if (cloud == null ||
          local.updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        toPush.add({
          'sync_id': local.syncId,
          'user_id': _userId,
          'name': local.name,
          'description': local.description,
          'created_at': _writeDate(local.createdAt),
          'updated_at': _writeDate(local.updatedAt),
          'deleted_at': _writeNullableDate(local.deletedAt),
        });
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
      await _remote.upsert('capital_groups', toPush, 'sync_id');
    }
  }

  Future<void> _applyGroup(
    Map<String, dynamic> cloud,
    CapitalGroupRow? existing,
  ) async {
    final syncId = cloud['sync_id'] as String;
    if (existing == null) {
      await _db
          .into(_db.capitalGroups)
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
      await (_db.update(
        _db.capitalGroups,
      )..where((row) => row.id.equals(existing.id))).write(
        CapitalGroupsCompanion(
          syncId: Value(syncId),
          name: Value(cloud['name'] as String),
          description: Value(cloud['description'] as String?),
          createdAt: Value(_readDate(cloud['created_at'])),
          updatedAt: Value(_readDate(cloud['updated_at'])),
          deletedAt: Value(_readNullableDate(cloud['deleted_at'])),
        ),
      );
    }
    if (_readNullableDate(cloud['deleted_at']) != null && existing != null) {
      await (_db.update(
        _db.cardsTable,
      )..where((row) => row.folderId.equals(existing.id))).write(
        CardsTableCompanion(
          folderId: const Value(null),
          updatedAt: Value(_clock()),
        ),
      );
    }
  }

  Future<Map<String, int>> _groupIdsBySyncId() async {
    final rows = await (_db.select(
      _db.capitalGroups,
    )..where((row) => row.deletedAt.isNull())).get();
    return {for (final row in rows) row.syncId: row.id};
  }

  // ------------------------------------------------------------------ cards

  Future<void> _syncCards() async {
    final localRows = await _db.select(_db.cardsTable).get();
    final cloudRows = await _remote.selectAll('cards');
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
          'user_id': _userId,
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
          'start_date': _writeDate(local.startDate),
          'created_at': _writeDate(local.createdAt),
          'updated_at': _writeDate(local.updatedAt),
        });
      }
    }
    for (final cloud in cloudRows) {
      final local = localById[cloud['id'] as String];
      if (local == null ||
          _readDate(cloud['updated_at']).isAfter(local.updatedAt)) {
        final groupSyncId = cloud['capital_group_id'] as String?;
        await _db
            .into(_db.cardsTable)
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
      await _remote.upsert('cards', toPush, 'id');
    }
  }

  // --------------------------------------------------------------- payments

  Future<void> _syncPayments() async {
    final localRows = await _db.select(_db.payments).get();
    final cloudRows = await _remote.selectAll('payments');
    final cloudById = {for (final row in cloudRows) row['id'] as String: row};
    final localById = {for (final row in localRows) row.id: row};
    final toPush = <Map<String, Object?>>[];
    for (final local in localRows) {
      final cloud = cloudById[local.id];
      if (cloud == null ||
          local.updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        toPush.add({
          'id': local.id,
          'user_id': _userId,
          'card_id': local.cardId,
          'scheduled_date': _writeNullableDate(local.scheduledDate),
          'amount_paid': local.amountPaid,
          'mora_cents': local.moraCents,
          'balance_after': local.balanceAfter,
          'payment_type': local.paymentType,
          'receipt_number': local.receiptNumber,
          'is_renewal': local.isRenewal,
          'created_at': _writeNullableDate(local.createdAt),
          'created_at_estimated': local.createdAtEstimated,
          'is_manual': local.isManual,
          'position': local.position,
          'updated_at': _writeDate(local.updatedAt),
          'deleted_at': _writeNullableDate(local.deletedAt),
        });
      }
    }
    final pulledCards = <String>{};
    for (final cloud in cloudRows) {
      final local = localById[cloud['id'] as String];
      if (local == null ||
          _readDate(cloud['updated_at']).isAfter(local.updatedAt)) {
        pulledCards.add(cloud['card_id'] as String);
        await _db
            .into(_db.payments)
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
      await _remote.upsert('payments', toPush, 'id');
    }
    // Running balances are derived; recompute them from the merged rows
    // instead of trusting whichever device wrote each row last.
    final knownCards = {
      for (final card in await _db.select(_db.cardsTable).get()) card.id,
    };
    final affected = pulledCards.intersection(knownCards);
    if (affected.isNotEmpty) {
      await PaymentLocalDataSource(_db)
          .recalculateBalances(affected, touchUpdatedAt: false);
    }
  }

  // ---------------------------------------------------------- notifications

  Future<void> _syncNotifications() async {
    final localRows = await _db.select(_db.operationalNotifications).get();
    final cloudRows = await _remote.selectAll('operational_notifications');
    final cloudByKey = {
      for (final row in cloudRows) row['event_key'] as String: row,
    };
    final localByKey = {for (final row in localRows) row.eventKey: row};
    final groupIds = await _groupIdsBySyncId();
    final groupSyncIds = {
      for (final entry in groupIds.entries) entry.value: entry.key,
    };
    final cardIds = {
      for (final card in await _db.select(_db.cardsTable).get()) card.id,
    };
    final now = _writeDate(_clock());
    final toPush = <Map<String, Object?>>[];
    for (final local in localRows) {
      final cloud = cloudByKey[local.eventKey];
      if (cloud == null || (local.isRead && cloud['is_read'] != true)) {
        toPush.add({
          'user_id': _userId,
          'event_key': local.eventKey,
          'type': local.type,
          'card_id': local.cardId,
          'capital_group_id': local.folderId == null
              ? null
              : groupSyncIds[local.folderId],
          'title': local.title,
          'message': local.message,
          'created_at': _writeDate(local.createdAt),
          'is_read': local.isRead || cloud?['is_read'] == true,
          'updated_at': now,
        });
      }
    }
    for (final cloud in cloudRows) {
      final key = cloud['event_key'] as String;
      final local = localByKey[key];
      if (local == null) {
        // Inserted directly, without the system alert: the other device
        // already raised it when the event happened.
        final cardId = cloud['card_id'] as String?;
        final groupSyncId = cloud['capital_group_id'] as String?;
        await _db
            .into(_db.operationalNotifications)
            .insert(
              OperationalNotificationsCompanion.insert(
                eventKey: key,
                type: cloud['type'] as String,
                cardId: Value(cardIds.contains(cardId) ? cardId : null),
                folderId: Value(
                  groupSyncId == null ? null : groupIds[groupSyncId],
                ),
                title: cloud['title'] as String,
                message: cloud['message'] as String,
                createdAt: _readDate(cloud['created_at']),
                isRead: Value(cloud['is_read'] as bool),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      } else if (cloud['is_read'] == true && !local.isRead) {
        await (_db.update(
          _db.operationalNotifications,
        )..where((row) => row.id.equals(local.id))).write(
          const OperationalNotificationsCompanion(isRead: Value(true)),
        );
      }
    }
    if (toPush.isNotEmpty) {
      await _remote.upsert(
        'operational_notifications',
        toPush,
        'user_id,event_key',
      );
    }
  }

  // ------------------------------------------------------------------- mora

  static String _dayKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// Deterministic identity: both devices accrue the same day for a card.
  static String moraSyncId(String cardId, DateTime day) =>
      '$cardId:${_dayKey(day)}';

  static DateTime _parseDay(Object? value) {
    final parts = (value as String).substring(0, 10).split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  Map<String, Object?> _moraToJson(MoraRow row, bool paid) => {
    'sync_id': moraSyncId(row.cardId, row.createdAt),
    'user_id': _userId,
    'card_id': row.cardId,
    'day': _dayKey(row.createdAt),
    'pagado': paid,
    'created_at': _writeDate(row.createdAt),
    'updated_at': _writeDate(_clock()),
  };

  /// Union of the days accrued on every device.
  Future<void> _syncMoraDays() async {
    final cloudRows = await _remote.selectAll('mora');
    _cloudMoraPaid
      ..clear()
      ..addAll({
        for (final row in cloudRows)
          row['sync_id'] as String: row['pagado'] as bool,
      });
    final localRows = await _db.select(_db.mora).get();
    final localKeys = {
      for (final row in localRows) moraSyncId(row.cardId, row.createdAt),
    };
    final cardIds = {
      for (final card in await _db.select(_db.cardsTable).get()) card.id,
    };
    for (final cloud in cloudRows) {
      final cardId = cloud['card_id'] as String;
      if (localKeys.contains(cloud['sync_id']) || !cardIds.contains(cardId)) {
        continue;
      }
      await _db
          .into(_db.mora)
          .insert(
            MoraCompanion.insert(
              cardId: cardId,
              createdAt: _parseDay(cloud['day']),
              pagado: Value(cloud['pagado'] as bool),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    // Keyed by sync id: legacy rows with two timestamps on one day would
    // otherwise send the same key twice, which Postgres rejects.
    final toPush = {
      for (final row in localRows)
        if (!_cloudMoraPaid.containsKey(moraSyncId(row.cardId, row.createdAt)))
          moraSyncId(row.cardId, row.createdAt): _moraToJson(row, row.pagado),
    }.values.toList();
    if (toPush.isNotEmpty) {
      await _remote.upsert('mora', toPush, 'sync_id');
      for (final row in toPush) {
        _cloudMoraPaid[row['sync_id'] as String] = row['pagado'] as bool;
      }
    }
  }

  Future<void> _syncMoraApplications() async {
    await _assignMissingSyncIds(_db.moraApplications, 'mora_applications');
    final moraRows = await _db.select(_db.mora).get();
    final keyById = {
      for (final row in moraRows) row.id: moraSyncId(row.cardId, row.createdAt),
    };
    final idByKey = {
      for (final entry in keyById.entries) entry.value: entry.key,
    };
    final paymentIds = {
      for (final row in await _db.select(_db.payments).get()) row.id,
    };
    final localRows = await _db.select(_db.moraApplications).get();
    final localById = {for (final row in localRows) row.syncId: row};
    final cloudRows = await _remote.selectAll('mora_applications');
    final cloudById = {
      for (final row in cloudRows) row['sync_id'] as String: row,
    };
    final toPush = <Map<String, Object?>>[];
    for (final local in localRows) {
      final moraKey = keyById[local.moraId];
      if (moraKey == null) continue;
      final cloud = cloudById[local.syncId];
      if (cloud == null || (local.reversed && cloud['reversed'] != true)) {
        toPush.add({
          'sync_id': local.syncId,
          'user_id': _userId,
          'payment_id': local.paymentId,
          'mora_sync_id': moraKey,
          'cents': local.cents,
          'reversed': local.reversed,
          'created_at': _writeDate(local.createdAt),
          'reversed_at': _writeNullableDate(local.reversedAt),
        });
      }
    }
    for (final cloud in cloudRows) {
      final local = localById[cloud['sync_id'] as String];
      final reversed = cloud['reversed'] as bool;
      if (local == null) {
        final moraId = idByKey[cloud['mora_sync_id'] as String];
        final paymentId = cloud['payment_id'] as String;
        if (moraId == null || !paymentIds.contains(paymentId)) continue;
        await _db
            .into(_db.moraApplications)
            .insert(
              MoraApplicationsCompanion.insert(
                syncId: Value(cloud['sync_id'] as String),
                paymentId: paymentId,
                moraId: moraId,
                cents: (cloud['cents'] as num).toInt(),
                reversed: Value(reversed),
                createdAt: _readDate(cloud['created_at']),
                reversedAt: Value(_readNullableDate(cloud['reversed_at'])),
              ),
            );
      } else if (reversed && !local.reversed) {
        await (_db.update(
          _db.moraApplications,
        )..where((row) => row.id.equals(local.id))).write(
          MoraApplicationsCompanion(
            reversed: const Value(true),
            reversedAt: Value(_readNullableDate(cloud['reversed_at'])),
          ),
        );
      }
    }
    if (toPush.isNotEmpty) {
      await _remote.upsert('mora_applications', toPush, 'sync_id');
    }
  }

  /// A day is paid while any of its applications stands. Days paid before
  /// applications were recorded keep their flag, and a paid flag on either
  /// side wins because such days cannot be reverted.
  Future<void> _reconcileMoraPaid() async {
    final applications = await _db.select(_db.moraApplications).get();
    final byMora = <int, List<MoraApplication>>{};
    for (final application in applications) {
      byMora.putIfAbsent(application.moraId, () => []).add(application);
    }
    final toPush = <String, Map<String, Object?>>{};
    for (final row in await _db.select(_db.mora).get()) {
      final key = moraSyncId(row.cardId, row.createdAt);
      final applied = byMora[row.id];
      final cloudPaid = _cloudMoraPaid[key];
      final paid = applied != null && applied.isNotEmpty
          ? applied.any((application) => !application.reversed)
          : row.pagado || (cloudPaid ?? false);
      if (paid != row.pagado) {
        await (_db.update(_db.mora)..where((mora) => mora.id.equals(row.id)))
            .write(MoraCompanion(pagado: Value(paid)));
      }
      if (cloudPaid != null && cloudPaid != paid) {
        toPush[key] = _moraToJson(row, paid);
      }
    }
    if (toPush.isNotEmpty) {
      await _remote.upsert('mora', toPush.values.toList(), 'sync_id');
      for (final row in toPush.values) {
        _cloudMoraPaid[row['sync_id'] as String] = row['pagado'] as bool;
      }
    }
  }

  /// The earliest checkpoint wins: a device that started counting later
  /// (e.g. a freshly installed phone) re-accrues the days it skipped.
  Future<void> _syncMoraTracking() async {
    final cloudRows = await _remote.selectAll('mora_tracking');
    final cloudByCard = {
      for (final row in cloudRows)
        row['card_id'] as String: _readDate(row['last_checked_at']),
    };
    final localByCard = {
      for (final row in await _db.select(_db.moraTracking).get())
        row.cardId: row.lastCheckedAt,
    };
    final cardIds = {
      for (final card in await _db.select(_db.cardsTable).get()) card.id,
    };
    final reaccrue = <String>{};
    for (final entry in cloudByCard.entries) {
      if (!cardIds.contains(entry.key)) continue;
      final local = localByCard[entry.key];
      if (local != null && !_day(entry.value).isBefore(_day(local))) continue;
      await _db
          .into(_db.moraTracking)
          .insertOnConflictUpdate(
            MoraTrackingCompanion.insert(
              cardId: entry.key,
              lastCheckedAt: entry.value,
            ),
          );
      if (local != null) reaccrue.add(entry.key);
    }
    for (final cardId in reaccrue) {
      try {
        await _db.transaction(
          () => MoraLocalDataSource(_db).accrue(cardId, now: _clock()),
        );
      } on Object {
        // A bad clock or a missing card must not block the rest of the sync.
        continue;
      }
    }
    if (reaccrue.isNotEmpty) await _syncMoraDays();

    final toPush = <Map<String, Object?>>[];
    for (final row in await _db.select(_db.moraTracking).get()) {
      final cloud = cloudByCard[row.cardId];
      if (cloud == null || _day(row.lastCheckedAt).isAfter(_day(cloud))) {
        toPush.add({
          'card_id': row.cardId,
          'user_id': _userId,
          'last_checked_at': _writeDate(row.lastCheckedAt),
          'updated_at': _writeDate(_clock()),
        });
      }
    }
    if (toPush.isNotEmpty) {
      await _remote.upsert('mora_tracking', toPush, 'card_id');
    }
  }

  static DateTime _day(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  // -------------------------------------------------------- payment changes

  /// Append-only audit trail: each device contributes what the other lacks.
  Future<void> _syncPaymentChanges() async {
    await _assignMissingSyncIds(_db.paymentChanges, 'payment_changes');
    final localRows = await _db.select(_db.paymentChanges).get();
    final localIds = {for (final row in localRows) row.syncId};
    final cloudRows = await _remote.selectAll('payment_changes');
    final cloudIds = {for (final row in cloudRows) row['sync_id'] as String};
    final paymentIds = {
      for (final row in await _db.select(_db.payments).get()) row.id,
    };
    final toPush = [
      for (final row in localRows)
        if (!cloudIds.contains(row.syncId))
          {
            'sync_id': row.syncId,
            'user_id': _userId,
            'payment_id': row.paymentId,
            'old_amount': row.oldAmount,
            'new_amount': row.newAmount,
            'old_mora_cents': row.oldMoraCents,
            'new_mora_cents': row.newMoraCents,
            'old_scheduled_date': _writeNullableDate(row.oldScheduledDate),
            'new_scheduled_date': _writeNullableDate(row.newScheduledDate),
            'old_type': row.oldType,
            'new_type': row.newType,
            'old_receipt': row.oldReceipt,
            'new_receipt': row.newReceipt,
            'created_at': _writeDate(row.createdAt),
          },
    ];
    for (final cloud in cloudRows) {
      final paymentId = cloud['payment_id'] as String;
      if (localIds.contains(cloud['sync_id']) ||
          !paymentIds.contains(paymentId)) {
        continue;
      }
      await _db
          .into(_db.paymentChanges)
          .insert(
            PaymentChangesCompanion.insert(
              syncId: Value(cloud['sync_id'] as String),
              paymentId: paymentId,
              oldAmount: (cloud['old_amount'] as num).toDouble(),
              newAmount: (cloud['new_amount'] as num).toDouble(),
              oldMoraCents: (cloud['old_mora_cents'] as num).toInt(),
              newMoraCents: (cloud['new_mora_cents'] as num).toInt(),
              oldScheduledDate: Value(
                _readNullableDate(cloud['old_scheduled_date']),
              ),
              newScheduledDate: Value(
                _readNullableDate(cloud['new_scheduled_date']),
              ),
              oldType: cloud['old_type'] as String,
              newType: cloud['new_type'] as String,
              oldReceipt: Value(cloud['old_receipt'] as String?),
              newReceipt: Value(cloud['new_receipt'] as String?),
              createdAt: _readDate(cloud['created_at']),
            ),
          );
    }
    if (toPush.isNotEmpty) {
      await _remote.upsert('payment_changes', toPush, 'sync_id');
    }
  }

  // ----------------------------------------------------------- credit plans

  Future<void> _syncCreditPlans() async {
    final localRows = await _db
        .customSelect(
          'SELECT id, sync_id, amount_cents, installments, installment_cents, '
          'is_active, updated_at, deleted_at FROM credit_plans',
        )
        .get();
    DateTime seconds(int value) =>
        DateTime.fromMillisecondsSinceEpoch(value * 1000);
    int toSeconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;
    final localById = {
      for (final row in localRows) row.read<String>('sync_id'): row,
    };
    final cloudRows = await _remote.selectAll('credit_plans');
    final cloudById = {
      for (final row in cloudRows) row['sync_id'] as String: row,
    };
    for (final cloud in cloudRows) {
      final syncId = cloud['sync_id'] as String;
      final local = localById[syncId];
      final cloudUpdatedAt = _readDate(cloud['updated_at']);
      if (local != null &&
          !cloudUpdatedAt.isAfter(seconds(local.read<int>('updated_at')))) {
        continue;
      }
      final deletedAt = _readNullableDate(cloud['deleted_at']);
      final values = [
        Variable.withInt((cloud['amount_cents'] as num).toInt()),
        Variable.withInt((cloud['installments'] as num).toInt()),
        Variable.withInt((cloud['installment_cents'] as num).toInt()),
        Variable.withInt(cloud['is_active'] == true ? 1 : 0),
        Variable.withInt(toSeconds(cloudUpdatedAt)),
        Variable<int>(deletedAt == null ? null : toSeconds(deletedAt)),
      ];
      try {
        if (local != null) {
          await _db.customUpdate(
            'UPDATE credit_plans SET amount_cents = ?, installments = ?, '
            'installment_cents = ?, is_active = ?, updated_at = ?, '
            'deleted_at = ? WHERE sync_id = ?',
            variables: [...values, Variable.withString(syncId)],
          );
          continue;
        }
        // The same plan created on both devices before syncing: adopt the
        // cloud identity for the local row that was never uploaded.
        final twin = localRows.where(
          (row) =>
              !cloudById.containsKey(row.read<String>('sync_id')) &&
              row.read<int>('amount_cents') == cloud['amount_cents'] &&
              row.read<int>('installments') == cloud['installments'] &&
              row.read<int>('installment_cents') == cloud['installment_cents'],
        );
        if (twin.isNotEmpty) {
          await _db.customUpdate(
            'UPDATE credit_plans SET sync_id = ?, is_active = ?, '
            'updated_at = ?, deleted_at = ? WHERE id = ?',
            variables: [
              Variable.withString(syncId),
              values[3],
              values[4],
              values[5],
              Variable.withInt(twin.first.read<int>('id')),
            ],
          );
        } else {
          await _db.customUpdate(
            'INSERT INTO credit_plans (amount_cents, installments, '
            'installment_cents, is_active, updated_at, deleted_at, sync_id) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            variables: [...values, Variable.withString(syncId)],
          );
        }
      } on Object {
        // Two different cloud plans collide on the same values locally;
        // keep the local catalog consistent and skip the duplicate.
        continue;
      }
    }
    final toPush = <Map<String, Object?>>[];
    // Pushed after pulling so a plan created on both devices uploads under
    // the identity it just adopted rather than as a second cloud row.
    final currentRows = await _db
        .customSelect(
          'SELECT sync_id, amount_cents, installments, installment_cents, '
          'is_active, updated_at, deleted_at FROM credit_plans',
        )
        .get();
    for (final local in currentRows) {
      final syncId = local.read<String>('sync_id');
      final cloud = cloudById[syncId];
      final updatedAt = seconds(local.read<int>('updated_at'));
      if (cloud == null || updatedAt.isAfter(_readDate(cloud['updated_at']))) {
        final deletedAt = local.readNullable<int>('deleted_at');
        toPush.add({
          'sync_id': syncId,
          'user_id': _userId,
          'amount_cents': local.read<int>('amount_cents'),
          'installments': local.read<int>('installments'),
          'installment_cents': local.read<int>('installment_cents'),
          'is_active': local.read<int>('is_active') == 1,
          'updated_at': _writeDate(updatedAt),
          'deleted_at': deletedAt == null
              ? null
              : _writeDate(seconds(deletedAt)),
        });
      }
    }
    if (toPush.isNotEmpty) {
      await _remote.upsert('credit_plans', toPush, 'sync_id');
    }
  }

  // ---------------------------------------------------- enterprise settings

  Future<void> _syncEnterpriseConfig() async {
    final local = await (_db.select(
      _db.enterpriseConfigs,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    final localSyncMetadata =
        await (_db.select(_db.syncMetadata)
              ..where((row) => row.key.equals('enterprise_config_updated_at')))
            .getSingleOrNull();
    final cloudRows = await _remote.selectAll('enterprise_configs');
    final cloud = cloudRows.isEmpty ? null : cloudRows.first;
    if (local == null && cloud == null) return;

    final localChangedAt = localSyncMetadata?.lastSyncedAt;
    if (local != null &&
        (cloud == null ||
            (localChangedAt != null &&
                localChangedAt.isAfter(_readDate(cloud['updated_at']))))) {
      final updatedAt = localChangedAt ?? _clock();
      await _remote.upsert('enterprise_configs', [
        {
          'user_id': _userId,
          'name': local.name,
          'phone': local.phone,
          'nit': local.nit,
          'email': local.email,
          'bank_account': local.bankAccount,
          'show_phone': local.showPhone,
          'show_nit': local.showNit,
          'show_email': local.showEmail,
          'show_bank_account': local.showBankAccount,
          'mora': local.mora,
          'collection_deadline_hour': local.collectionDeadlineHour,
          'collection_deadline_minute': local.collectionDeadlineMinute,
          'collection_reminder_minutes': local.collectionReminderMinutes,
          'updated_at': _writeDate(updatedAt),
        },
      ], 'user_id');
      return;
    }

    if (cloud != null &&
        (local == null ||
            localChangedAt == null ||
            _readDate(cloud['updated_at']).isAfter(localChangedAt))) {
      final companion = EnterpriseConfigsCompanion(
        id: const Value(1),
        name: Value(cloud['name'] as String),
        phone: Value(cloud['phone'] as String),
        nit: Value(cloud['nit'] as String),
        email: Value(cloud['email'] as String),
        bankAccount: Value(cloud['bank_account'] as String),
        showPhone: Value(cloud['show_phone'] as bool),
        showNit: Value(cloud['show_nit'] as bool),
        showEmail: Value(cloud['show_email'] as bool),
        showBankAccount: Value(cloud['show_bank_account'] as bool),
        mora: Value((cloud['mora'] as num).toInt()),
        collectionDeadlineHour: Value(
          (cloud['collection_deadline_hour'] as num).toInt(),
        ),
        collectionDeadlineMinute: Value(
          (cloud['collection_deadline_minute'] as num).toInt(),
        ),
        collectionReminderMinutes: Value(
          (cloud['collection_reminder_minutes'] as num).toInt(),
        ),
      );
      if (local == null) {
        await _db.into(_db.enterpriseConfigs).insert(companion);
      } else {
        await (_db.update(
          _db.enterpriseConfigs,
        )..where((row) => row.id.equals(1))).write(companion);
      }
      await _db
          .into(_db.syncMetadata)
          .insertOnConflictUpdate(
            SyncMetadataCompanion.insert(
              key: 'enterprise_config_updated_at',
              lastSyncedAt: Value(_readDate(cloud['updated_at'])),
            ),
          );
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _assignMissingSyncIds(TableInfo table, String name) async {
    final rows = await _db
        .customSelect(
          "SELECT id FROM $name WHERE sync_id = ''",
          readsFrom: {table},
        )
        .get();
    for (final row in rows) {
      await _db.customUpdate(
        'UPDATE $name SET sync_id = ? WHERE id = ?',
        variables: [
          Variable.withString(const Uuid().v4()),
          Variable.withInt(row.read<int>('id')),
        ],
        updates: {table},
      );
    }
  }

  static String _writeDate(DateTime value) => value.toUtc().toIso8601String();

  static String? _writeNullableDate(DateTime? value) =>
      value == null ? null : _writeDate(value);

  static DateTime _readDate(Object? value) =>
      DateTime.parse(value as String).toLocal();

  static DateTime? _readNullableDate(Object? value) =>
      value == null ? null : _readDate(value);
}
