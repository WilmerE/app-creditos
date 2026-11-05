import 'dart:io';

import 'package:flutter/material.dart';

class ClientAvatar extends StatelessWidget {
  const ClientAvatar({
    super.key,
    required this.name,
    this.photoPath,
    this.radius = 28,
  });

  final String name;
  final String? photoPath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(initial, style: TextStyle(fontSize: radius * 0.8)),
    );
    final path = photoPath;
    if (path == null || path.isEmpty) return fallback;

    return ClipOval(
      child: Image.file(
        File(path),
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
