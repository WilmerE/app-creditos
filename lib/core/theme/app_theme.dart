import 'package:flutter/material.dart';

abstract final class HistoryColors {
  static const paid = Color(0xFF2E7D32);
  static const pending = Color(0xFFF9A825);
  static const overdue = Color(0xFFC62828);
  static const locked = Color(0xFF616161);
}

abstract final class AppTheme {
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
  );
}
