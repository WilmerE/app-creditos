import 'dart:io';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

@lazySingleton
class ClientPhotoStorage {
  ClientPhotoStorage() : _root = null;

  /// Stores photos under [root]; used by tests instead of path_provider.
  ClientPhotoStorage.withRoot(Directory root) : _root = root;

  final Directory? _root;

  Future<Directory> _photosDirectory() async {
    final base = _root ?? await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'client_photos'))
        .create(recursive: true);
  }

  /// Copies the picked image into the app directory and returns its new path.
  Future<String> store(String sourcePath, String clientId) async {
    final directory = await _photosDirectory();
    final extension = p.extension(sourcePath).toLowerCase();
    final fileName =
        '${clientId}_${DateTime.now().millisecondsSinceEpoch}'
        '${extension.isEmpty ? '.jpg' : extension}';
    final copied = await File(sourcePath)
        .copy(p.join(directory.path, fileName));
    return copied.path;
  }

  /// Writes a photo downloaded from the cloud under its original file name.
  Future<String> storeBytes(Uint8List bytes, String fileName) async {
    final directory = await _photosDirectory();
    final file = File(p.join(directory.path, p.basename(fileName)));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Deletes only files managed by this storage, never arbitrary paths.
  Future<void> delete(String path) async {
    final directory = await _photosDirectory();
    if (!p.isWithin(directory.path, path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
