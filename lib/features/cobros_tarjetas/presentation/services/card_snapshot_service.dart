import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Captures the clean card subtree and stores it as a temporary PNG.
class CardSnapshotService {
  const CardSnapshotService();
  static const _galleryChannel = MethodChannel('app_creditos/media_gallery');
  static const _maxImageWidth = 1200;
  static const _portraitWidthToHeight = 0.70;

  Future<File> capture(GlobalKey boundaryKey, {String? fileName}) async {
    final context = boundaryKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('La tarjeta todavía no está lista para exportarse.');
    }
    final sourceImage = await renderObject.toImage(pixelRatio: 2.5);
    try {
      final image = await _fitPortrait(sourceImage);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('No se pudo generar la imagen.');
        final directory = await getTemporaryDirectory();
        final safeName = (fileName ?? 'tarjeta-digital').replaceAll(
          RegExp(r'[^a-zA-Z0-9_-]'),
          '_',
        );
        final file = File('${directory.path}/$safeName.png');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        return file;
      } finally {
        image.dispose();
      }
    } finally {
      sourceImage.dispose();
    }
  }

  Future<String> save(File source, {String? fileName}) async {
    final safeName = (fileName ?? 'tarjeta-digital').replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    if (Platform.isAndroid) {
      final location = await _galleryChannel.invokeMethod<String>('saveImage', {
        'fileName': '$safeName.png',
        'bytes': await source.readAsBytes(),
      });
      return location ?? 'V&S Inversiones/$safeName.png';
    }

    final directory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final destination = File('${directory.path}/$safeName.png');
    await source.copy(destination.path);
    return destination.path;
  }

  Future<ui.Image> _fitPortrait(ui.Image source) async {
    final scale = math.min(1.0, _maxImageWidth / source.width).toDouble();
    final width = (source.width * scale).round();
    final contentHeight = (source.height * scale).round();
    final height = math.max(
      contentHeight,
      (width / _portraitWidthToHeight).ceil(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.scale(scale);
    canvas.drawImage(
      source,
      ui.Offset.zero,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  Future<ShareResult> share(File image, {String? text}) => SharePlus.instance
      .share(ShareParams(files: [XFile(image.path)], text: text));
}
