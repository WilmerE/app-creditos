import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/clientes/data/services/client_photo_storage.dart';
import '../../features/cobros_tarjetas/data/credit_plan_repository.dart';
import '../database/app_database.dart';
import 'delta_sync.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';

enum SyncPhase {
  notConfigured,
  needsAuthentication,
  accountMismatch,
  syncing,
  synchronized,
  offline,
}

/// Keeps SQLite authoritative while exchanging newer rows with the signed-in
/// user's Supabase account. See [SyncEngine] for the per-entity merge rules.
class SupabaseDeltaSync extends ChangeNotifier
    with WidgetsBindingObserver
    implements DeltaSync {
  SupabaseDeltaSync(
    this._database,
    this._client, {
    Connectivity? connectivity,
    ClientPhotoStorage? photos,
  }) : _connectivity = connectivity ?? Connectivity(),
       _photos = photos ?? ClientPhotoStorage();

  final AppDatabase _database;
  final ClientPhotoStorage _photos;
  final SupabaseClient? _client;
  final Connectivity _connectivity;
  SyncPhase _phase = SyncPhase.notConfigured;
  Timer? _retryTimer;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final List<StreamSubscription<dynamic>> _localSubscriptions = [];
  final Map<String, Future<bool>> _accountBindings = {};
  Timer? _localChangeTimer;
  bool _networkAvailable = true;
  bool _running = false;
  int _localChangeRevision = 0;
  int _syncedRevision = 0;

  SyncPhase get phase => _phase;
  SupabaseClient? get client => _client;
  User? get currentUser => _client?.auth.currentUser;
  bool get isConfigured => _client != null;
  bool get isOffline => !_networkAvailable || _phase == SyncPhase.offline;
  Stream<AuthState>? get authStateChanges => _client?.auth.onAuthStateChange;

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
    // connectivity_plus can throw while opening its native event stream on
    // Windows. Periodic and lifecycle checks below still keep sync responsive.
    if (defaultTargetPlatform != TargetPlatform.windows) {
      _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen(
        _handleConnectivity,
        onError: (Object _) => unawaited(synchronize()),
      );
    }
    if (_localSubscriptions.isEmpty) {
      _watchLocalChanges(_database.select(_database.clientsTable).watch());
      _watchLocalChanges(_database.select(_database.capitalGroups).watch());
      _watchLocalChanges(_database.select(_database.cardsTable).watch());
      _watchLocalChanges(_database.select(_database.payments).watch());
      _watchLocalChanges(_database.select(_database.enterpriseConfigs).watch());
      _watchLocalChanges(_database.select(_database.mora).watch());
      _watchLocalChanges(_database.select(_database.moraApplications).watch());
      _watchLocalChanges(_database.select(_database.paymentChanges).watch());
      _watchLocalChanges(
        _database.select(_database.operationalNotifications).watch(),
      );
      // Unlike select().watch(), tableUpdates has no initial event to skip.
      _watchLocalChanges(
        _database.tableUpdates(
          TableUpdateQuery.onTableName(CreditPlanRepository.tableUpdate.table),
        ),
        skipInitial: false,
      );
    }
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

  void _watchLocalChanges<T>(Stream<T> changes, {bool skipInitial = true}) {
    _localSubscriptions.add(
      changes.skip(skipInitial ? 1 : 0).listen((_) {
        _localChangeRevision++;
        _localChangeTimer?.cancel();
        _localChangeTimer = Timer(
          const Duration(milliseconds: 600),
          () => unawaited(synchronize()),
        );
      }),
    );
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

  Future<AuthResponse> register(
    String fullName,
    String email,
    String password,
  ) async {
    final client = _requireOnlineClient();
    return client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName.trim()},
    );
  }

  /// Allows bootstrap registration only while the Supabase project has no user.
  Future<bool> isRootAccountAvailable() async {
    final client = _requireOnlineClient();
    final result = await client.rpc('is_root_account_available');
    return result == true;
  }

  Future<void> sendPasswordReset(String email) async {
    final client = _requireOnlineClient();
    await client.auth.resetPasswordForEmail(email);
  }

  Future<void> resendSignupConfirmation(String email) async {
    final client = _requireOnlineClient();
    await client.auth.resend(type: OtpType.signup, email: email);
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
    required OtpType type,
  }) async {
    final client = _requireOnlineClient();
    return client.auth.verifyOTP(email: email, token: token, type: type);
  }

  Future<UserResponse> updatePassword(String password) async {
    final client = _requireOnlineClient();
    return client.auth.updateUser(UserAttributes(password: password));
  }

  SupabaseClient _requireOnlineClient() {
    final client = _client;
    if (client == null) throw StateError('Supabase no está configurado.');
    if (!_networkAvailable) {
      throw StateError(
        'No hay conexión a internet. Conéctate para autenticarte.',
      );
    }
    return client;
  }

  Future<bool> isAccountAllowedLocally(String userId) => _isBoundTo(userId);

  bool get hasPendingChanges =>
      _localChangeRevision > _syncedRevision ||
      _phase != SyncPhase.synchronized;

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
    final syncingRevision = _localChangeRevision;
    _setPhase(SyncPhase.syncing);
    try {
      if (!await _isBoundTo(user.id)) {
        _setPhase(SyncPhase.accountMismatch);
        return;
      }
      await SyncEngine(
        _database,
        SupabaseSyncRemote(client),
        user.id,
        photos: _photos,
      ).run();
      _syncedRevision = syncingRevision;
      _setPhase(SyncPhase.synchronized);
    } on Object {
      // Offline, RLS denial, or a missing server migration all leave SQLite
      // usable; retry on the next periodic tick or explicit user request.
      _setPhase(SyncPhase.offline);
    } finally {
      _running = false;
    }
  }

  Future<bool> _isBoundTo(String userId) =>
      _accountBindings.putIfAbsent(userId, () => _checkAndBindAccount(userId));

  Future<bool> _checkAndBindAccount(String userId) async {
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

  void _setPhase(SyncPhase next) {
    if (_phase == next) return;
    _phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _localChangeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    for (final subscription in _localSubscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
