import '../entities/client.dart';

abstract interface class ClientRepository {
  /// Emits the active clients (optionally filtered by name, DPI or alias)
  /// every time the local database changes.
  Stream<List<Client>> watchClients({String query = ''});

  Future<Client?> getById(String id);

  /// Creates or updates [client]. When [newPhotoSourcePath] is provided the
  /// image is copied into the app storage and its path replaces `photoPath`.
  Future<void> save(Client client, {String? newPhotoSourcePath});

  Future<void> delete(String id);
}
