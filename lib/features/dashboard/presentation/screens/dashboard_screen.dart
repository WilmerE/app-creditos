import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../injection_container.dart';
import '../../../clientes/presentation/widgets/client_avatar.dart';
import '../../../cobros_tarjetas/domain/entities/credit_card.dart';
import '../../../cobros_tarjetas/presentation/screens/card_detail_screen.dart';
import '../../data/drift_dashboard_repository.dart';
import '../../domain/dashboard_repository.dart';
import '../bloc/dashboard_cubit.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        DashboardCubit(DriftDashboardRepository(getIt<AppDatabase>()))..start(),
    child: const DashboardView(),
  );
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  static const _filters = [
    (
      DashboardFilter.active,
      CardStatus.active,
      'Activas / Al día',
      Icons.credit_card,
      Color(0xFF1565C0),
    ),
    (
      DashboardFilter.debtor,
      CardStatus.debtor,
      'En mora / Deudoras',
      Icons.warning_amber,
      HistoryColors.overdue,
    ),
    (
      DashboardFilter.renewal,
      CardStatus.renewal,
      'En renovación',
      Icons.autorenew,
      Color(0xFF6A1B9A),
    ),
    (
      DashboardFilter.paid,
      CardStatus.paid,
      'Liquidadas / Pagadas',
      Icons.check_circle_outline,
      HistoryColors.paid,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard de cobros')),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          if (state.status == DashboardStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == DashboardStatus.error) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No se pudo cargar el dashboard.'),
                  TextButton(
                    onPressed: context.read<DashboardCubit>().start,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final metricWidth = constraints.maxWidth >= 1000
                  ? (constraints.maxWidth - 64) / 3
                  : constraints.maxWidth >= 600
                  ? (constraints.maxWidth - 48) / 2
                  : constraints.maxWidth - 32;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final (filter, status, title, icon, color)
                          in _filters)
                        SizedBox(
                          width: metricWidth,
                          child: _MetricCard(
                            title: title,
                            value: '${state.count(status)}',
                            icon: icon,
                            color: color,
                            selected: state.filter == filter,
                            onTap: () => context
                                .read<DashboardCubit>()
                                .selectFilter(filter),
                          ),
                        ),
                      SizedBox(
                        width: metricWidth,
                        child: _MetricCard(
                          title: 'Caja diaria',
                          value:
                              'Proyectado: ${CurrencyFormatter.formatGtq(state.projectedToday)}\n'
                              'Abonado estimado: ${CurrencyFormatter.formatGtq(state.estimatedPaidToday)}',
                          icon: Icons.account_balance_wallet_outlined,
                          color: const Color(0xFF00695C),
                          selected: state.filter == DashboardFilter.cash,
                          onTap: () => context
                              .read<DashboardCubit>()
                              .selectFilter(DashboardFilter.cash),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Caja estimada: suma los importes acumulados de cuotas editadas hoy; '
                    'no representa necesariamente abonos recibidos hoy. '
                    'La proyección suma las cuotas programadas para hoy.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Los estados se muestran tal como están guardados; no cambian automáticamente al registrar pagos.',
                  ),
                  const SizedBox(height: 24),
                  Text(switch (state.filter) {
                    DashboardFilter.active => 'Tarjetas activas / al día',
                    DashboardFilter.debtor => 'Tarjetas en mora / deudoras',
                    DashboardFilter.renewal => 'Tarjetas en renovación',
                    DashboardFilter.paid => 'Tarjetas pagadas',
                    DashboardFilter.cash => 'Cuotas programadas o editadas hoy',
                  }, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (state.visibleCards.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No hay tarjetas para este filtro.'),
                      ),
                    )
                  else
                    for (final card in state.visibleCards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DashboardCardTile(card: card),
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: selected ? color.withValues(alpha: 0.10) : null,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? color : Theme.of(context).dividerColor,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Ver detalles',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DashboardCardTile extends StatelessWidget {
  const _DashboardCardTile({required this.card});
  final DashboardCard card;

  Color get _statusColor => switch (card.status) {
    CardStatus.active => const Color(0xFF1565C0),
    CardStatus.debtor => HistoryColors.overdue,
    CardStatus.renewal => const Color(0xFF6A1B9A),
    CardStatus.paid => HistoryColors.paid,
    CardStatus.archived => HistoryColors.locked,
  };

  Future<void> _changeStatus(BuildContext context, CardStatus status) async {
    try {
      await context.read<DashboardCubit>().changeStatus(card.id, status);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Estado actualizado.')));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar el estado: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClientAvatar(
                name: card.clientName,
                photoPath: card.photoPath,
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.clientName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (card.alias != null && card.alias!.trim().isNotEmpty)
                      Text(card.alias!),
                    Text(
                      card.status.label,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<CardStatus>(
                tooltip: 'Cambiar estado',
                onSelected: (status) => _changeStatus(context, status),
                itemBuilder: (_) => [
                  for (final status in CardStatus.values.where(
                    (status) =>
                        status != CardStatus.archived && status != card.status,
                  ))
                    PopupMenuItem(value: status, child: Text(status.label)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Saldo pendiente: ${CurrencyFormatter.formatGtq(card.pendingBalance)} · '
            'Cuotas restantes: ${card.remainingInstallments}',
          ),
          if (card.status == CardStatus.paid && card.pendingBalance > 0.005)
            const Text(
              'Atención: el estado pagado tiene saldo pendiente.',
              style: TextStyle(color: HistoryColors.overdue),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('dashboard-details-${card.id}'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CardDetailScreen(cardId: card.id),
                ),
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ver detalles'),
            ),
          ),
        ],
      ),
    ),
  );
}
