import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

class CreditosApp extends StatelessWidget {
  const CreditosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestión de Créditos',
      theme: AppTheme.light,
      home: const Scaffold(
        body: Center(child: Text('Gestión de Créditos y Cobros')),
      ),
    );
  }
}
