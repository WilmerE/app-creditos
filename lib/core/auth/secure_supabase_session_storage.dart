import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores Supabase sessions in the platform's protected credential store.
/// Existing sessions in supabase_flutter's SharedPreferences storage are
/// migrated lazily on the first read, without requiring a network connection.
class SecureSupabaseSessionStorage extends LocalStorage {
  SecureSupabaseSessionStorage({
    required String persistSessionKey,
    FlutterSecureStorage? secureStorage,
  }) : _persistSessionKey = persistSessionKey,
       _secureStorage = secureStorage ?? FlutterSecureStorage(),
       _legacyStorage = SharedPreferencesLocalStorage(
         persistSessionKey: persistSessionKey,
       );

  final String _persistSessionKey;
  final FlutterSecureStorage _secureStorage;
  final SharedPreferencesLocalStorage _legacyStorage;

  @override
  Future<void> initialize() => _legacyStorage.initialize();

  @override
  Future<bool> hasAccessToken() async {
    if (await _secureStorage.containsKey(key: _persistSessionKey)) return true;
    return _legacyStorage.hasAccessToken();
  }

  @override
  Future<String?> accessToken() async {
    final secureSession = await _secureStorage.read(key: _persistSessionKey);
    if (secureSession != null) return secureSession;

    final legacySession = await _legacyStorage.accessToken();
    if (legacySession == null) return null;

    await _secureStorage.write(key: _persistSessionKey, value: legacySession);
    await _legacyStorage.removePersistedSession();
    return legacySession;
  }

  @override
  Future<void> persistSession(String persistSessionString) => _secureStorage
      .write(key: _persistSessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() async {
    await _secureStorage.delete(key: _persistSessionKey);
    await _legacyStorage.removePersistedSession();
  }
}
