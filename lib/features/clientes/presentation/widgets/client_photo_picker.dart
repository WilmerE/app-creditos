import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'client_avatar.dart';

/// Circular photo preview with a floating edit button. Offers the camera only
/// where the platform supports it (phones/tablets) and gallery/file otherwise.
class ClientPhotoPicker extends StatelessWidget {
  const ClientPhotoPicker({
    super.key,
    required this.name,
    required this.onPicked,
    this.currentPhotoPath,
    this.pendingPhotoPath,
    this.onRemoved,
    this.size = 120,
    this.picker,
  });

  final String name;
  final String? currentPhotoPath;
  final String? pendingPhotoPath;
  final ValueChanged<String> onPicked;
  final VoidCallback? onRemoved;
  final double size;
  final ImagePicker? picker;

  ImagePicker get _imagePicker => picker ?? ImagePicker();

  bool get _hasPhoto =>
      (pendingPhotoPath ?? currentPhotoPath)?.isNotEmpty ?? false;

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (file != null) onPicked(file.path);
    } on Object {
      // Permission denied or picker cancelled by the platform.
    }
  }

  Future<void> _showOptions(BuildContext context) async {
    final picker = _imagePicker;
    final canUseCamera = picker.supportsImageSource(ImageSource.camera);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (canUseCamera)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                canUseCamera ? 'Elegir de la galería' : 'Elegir archivo',
              ),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            if (_hasPhoto && onRemoved != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Quitar foto'),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'camera':
        await _pick(ImageSource.camera);
      case 'gallery':
        await _pick(ImageSource.gallery);
      case 'remove':
        onRemoved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = pendingPhotoPath;
    final preview = pending != null
        ? ClipOval(
            child: Image.file(
              File(pending),
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          )
        : ClientAvatar(
            name: name,
            photoPath: currentPhotoPath,
            radius: size / 2,
          );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: preview),
          Positioned(
            right: -4,
            bottom: -4,
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Editar foto',
              onPressed: () => _showOptions(context),
              child: const Icon(Icons.edit),
            ),
          ),
        ],
      ),
    );
  }
}
