import 'package:injectable/injectable.dart';

import '../../domain/entities/client.dart';
import '../../domain/repositories/client_repository.dart';
import '../datasources/client_local_datasource.dart';
import '../services/client_photo_storage.dart';

@LazySingleton(as: ClientRepository)
class ClientRepositoryImpl implements ClientRepository {
  ClientRepositoryImpl(this._local, this._photos);

  final ClientLocalDataSource _local;
  final ClientPhotoStorage _photos;

  @override
  Stream<List<Client>> watchClients({String query = ''}) {
    return _local.watchClients(query: query);
  }

  @override
  Future<Client?> getById(String id) => _local.getById(id);

  @override
  Future<void> save(Client client, {String? newPhotoSourcePath}) async {
    final existing = await _local.getById(client.id);
    final previousPhoto = existing?.photoPath;

    var toSave = client.copyWith(updatedAt: DateTime.now());
    if (newPhotoSourcePath != null) {
      final stored = await _photos.store(newPhotoSourcePath, client.id);
      toSave = toSave.copyWith(photoPath: stored);
    }

    if (existing == null) {
      await _local.insert(toSave);
    } else {
      await _local.update(toSave);
    }

    if (previousPhoto != null && previousPhoto != toSave.photoPath) {
      try {
        await _photos.delete(previousPhoto);
      } on Object {
        // The client was saved; a leftover image file is harmless.
      }
    }
  }

  @override
  Future<void> delete(String id) => _local.softDelete(id, DateTime.now());
}
