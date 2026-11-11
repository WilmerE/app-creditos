import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Captures the clean card subtree and stores it as a temporary PNG.
class CardSnapshotService {
  const CardSnapshotService();

  Future<File> capture(GlobalKey boundaryKey, {String? fileName}) async {
    final context = boundaryKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('La tarjeta todavía no está lista para exportarse.');
    }
    final image = await renderObject.toImage(pixelRatio: 2.5);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('No se pudo generar la imagen.');
      final directory = await getTemporaryDirectory();
      final safeName = (fileName ?? 'tarjeta-digital')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${directory.path}/$safeName.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file;
    } finally {
      image.dispose();
    }
  }

  Future<File> save(File source, {String? fileName}) async {
    final directory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final safeName = (fileName ?? 'tarjeta-digital')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final destination = File('${directory.path}/$safeName.png');
    return source.copy(destination.path);
  }

  Future<ShareResult> share(File image, {String? text}) =>
      SharePlus.instance.share(
        ShareParams(files: [XFile(image.path)], text: text),
      );
}
