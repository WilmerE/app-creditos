import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/database/app_database.dart';
import 'core/database/database_seed.dart';
import 'core/theme/app_theme.dart';
import 'features/clientes/presentation/screens/client_list_screen.dart';
import 'features/cobros_tarjetas/presentation/screens/card_navigation.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/enterprise/presentation/enterprise_config_screen.dart';
import 'injection_container.dart';

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

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  bool _seeding = false;

  Future<void> _seed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cargar datos de prueba'),
        content: const Text(
          'Se crearán 80 clientes ficticios y 200 tarjetas en esta base local. '
          'Solo se permite en una base sin clientes, tarjetas ni pagos. '
          'No utilice estos datos para cobros ni contacte los teléfonos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cargar datos'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _seeding = true);
    try {
      final result = await DatabaseSeed(getIt<AppDatabase>()).run();
      if (!mounted) return;
      final message = switch (result) {
        DatabaseSeedResult.inserted =>
          'Se cargaron 80 clientes y 200 tarjetas de prueba.',
        DatabaseSeedResult.alreadyInserted =>
          'Los datos de prueba ya fueron cargados.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron cargar los datos de prueba: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Gestión de Créditos y Cobros'),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DashboardScreen(),
                ),
              ),
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Dashboard'),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EnterpriseConfigScreen(),
                ),
              ),
              icon: const Icon(Icons.business_outlined),
              label: const Text('Configuración empresarial'),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _seeding ? null : _seed,
                icon: const Icon(Icons.science_outlined),
                label: Text(
                  _seeding ? 'Cargando datos...' : 'Cargar datos de prueba',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
