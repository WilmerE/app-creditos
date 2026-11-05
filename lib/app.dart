import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/clientes/presentation/screens/client_list_screen.dart';
import 'features/cobros_tarjetas/presentation/screens/card_navigation.dart';

class CreditosApp extends StatelessWidget {
  const CreditosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestión de Créditos',
      theme: AppTheme.light,
      home: const _HomeScreen(),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Gestión de Créditos y Cobros'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => openCardCreation(context),
              icon: const Icon(Icons.add_card),
              label: const Text('Nueva tarjeta'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ClientListScreen(
                    onCreateCard: (client) => createCardFor(context, client),
                    onOpenCards: (client) => openClientCards(context, client),
                  ),
                ),
              ),
              icon: const Icon(Icons.people_outline),
              label: const Text('Clientes'),
            ),
          ],
        ),
      ),
    );
  }
}
