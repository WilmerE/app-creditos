import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ClientPhotoCropDialog extends StatefulWidget {
  const ClientPhotoCropDialog({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ClientPhotoCropDialog> createState() => _ClientPhotoCropDialogState();
}

class _ClientPhotoCropDialogState extends State<ClientPhotoCropDialog> {
  final _cropKey = GlobalKey();
  final _transform = TransformationController();
  ui.Image? _image;
  Object? _error;
  Object? _saveError;
  double _zoom = 1;
  double? _viewportSide;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onTransformChanged() {
    if (!mounted) return;
    final scale = _transform.value.getMaxScaleOnAxis().clamp(1.0, 4.0);
    if ((scale - _zoom).abs() > 0.01) setState(() => _zoom = scale);
  }

  void _setZoom(
    double value,
    double side,
    double childWidth,
    double childHeight,
  ) {
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (side - childWidth * value) / 2,
        (side - childHeight * value) / 2,
        0,
        1,
      )
      ..scaleByDouble(value, value, value, 1);
  }

  Future<void> _saveCrop() async {
    final boundary =
        _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _saving = true);
    try {
      final cropped = await boundary.toImage(pixelRatio: 2);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (data == null) throw StateError('No se pudo preparar la imagen.');
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'client_photo_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (mounted) Navigator.of(context).pop(file.path);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = error;
        });
      }
    }
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransformChanged)
      ..dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null
              ? _buildError(context)
              : image == null
              ? const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _buildEditor(context, image),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.broken_image_outlined, size: 48),
      const SizedBox(height: 12),
      const Text('No se pudo abrir la imagen.'),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cerrar'),
      ),
    ],
  );

  Widget _buildEditor(BuildContext context, ui.Image image) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(400.0, constraints.maxWidth);
      final cover = math.max(side / image.width, side / image.height);
      final childWidth = image.width * cover;
      final childHeight = image.height * cover;
      if (_viewportSide != side) {
        _viewportSide = side;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setZoom(1, side, childWidth, childHeight);
        });
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ajustar foto', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Mueve y acerca la imagen para encuadrarla.'),
          const SizedBox(height: 20),
          Center(
            child: SizedBox.square(
              dimension: side,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    key: _cropKey,
                    child: ClipRect(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        minScale: 1,
                        maxScale: 4,
                        child: Image.file(
                          File(widget.imagePath),
                          width: childWidth,
                          height: childHeight,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(painter: _CircularCropMaskPainter()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.remove),
              Expanded(
                child: Slider(
                  value: _zoom,
                  min: 1,
                  max: 4,
                  onChanged: (value) =>
                      _setZoom(value, side, childWidth, childHeight),
                ),
              ),
              const Icon(Icons.add),
            ],
          ),
          if (_saveError != null)
            Text(
              'No se pudo guardar el recorte.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _saveCrop,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Usar foto'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _CircularCropMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final circle = Rect.fromCircle(
      center: bounds.center,
      radius: math.min(size.width, size.height) / 2 - 2,
    );
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(bounds),
      Path()..addOval(circle),
    );
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawOval(
      circle,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
