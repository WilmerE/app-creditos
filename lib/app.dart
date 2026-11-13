import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/auth_gate.dart';

class CreditosApp extends StatelessWidget {
  const CreditosApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Llave en Mano',
    theme: AppTheme.light,
    home: const AuthGate(),
  );
}
