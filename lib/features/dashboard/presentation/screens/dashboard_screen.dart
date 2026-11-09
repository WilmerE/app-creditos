import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/contact_launcher.dart';
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
    (
      DashboardFilter.deactivated,
      CardStatus.deactivated,
      'Desactivadas',
      Icons.block,
      HistoryColors.locked,
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
                      SizedBox(
                        width: metricWidth,
                        child: _MetricCard(
                          title: 'Cobros de hoy',
                          value:
                              'Pendientes: ${state.pendingDueTodayCount}\n'
                              'Pagados: ${state.paidDueTodayCount}',
                          icon: Icons.today,
                          color: const Color(0xFF00695C),
                          selected: state.filter == DashboardFilter.todayDue,
                          onTap: () => context
                              .read<DashboardCubit>()
                              .selectFilter(DashboardFilter.todayDue),
                        ),
                      ),
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
                    'Al liquidar el saldo, la tarjeta pasa a En renovación; al emitir una nueva, la anterior queda Pagada.',
                  ),
                  const SizedBox(height: 24),
                  Text(switch (state.filter) {
                    DashboardFilter.active => 'Tarjetas activas / al día',
                    DashboardFilter.debtor => 'Tarjetas en mora / deudoras',
                    DashboardFilter.renewal => 'Tarjetas en renovación',
                    DashboardFilter.paid => 'Tarjetas pagadas',
                    DashboardFilter.deactivated => 'Tarjetas desactivadas',
                    DashboardFilter.todayDue => 'Cobros de hoy',
                    DashboardFilter.cash => 'Cuotas programadas o editadas hoy',
                  }, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (state.filter == DashboardFilter.todayDue)
                    _TodayDueList(payments: state.todayDuePayments)
                  else
                    _DashboardCardsList(cards: state.visibleCards),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

enum _TodayDueGroup { pending, paid }

class _TodayDueList extends StatefulWidget {
  const _TodayDueList({required this.payments});

  final List<TodayDuePayment> payments;

  @override
  State<_TodayDueList> createState() => _TodayDueListState();
}

class _TodayDueListState extends State<_TodayDueList> {
  final _searchController = TextEditingController();
  _TodayDueGroup _group = _TodayDueGroup.pending;
  String _query = '';

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .trim();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalize(_query);
    final filtered = widget.payments
        .where((due) {
          if ((_group == _TodayDueGroup.paid) != due.isPaid) return false;
          return query.isEmpty ||
              _normalize(due.card.clientName).contains(query) ||
              _normalize(due.card.alias ?? '').contains(query);
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_TodayDueGroup>(
          segments: [
            ButtonSegment(
              value: _TodayDueGroup.pending,
              label: Text(
                'Pendientes (${widget.payments.where((p) => !p.isPaid).length})',
              ),
              icon: const Icon(Icons.pending_actions),
            ),
            ButtonSegment(
              value: _TodayDueGroup.paid,
              label: Text(
                'Pagados (${widget.payments.where((p) => p.isPaid).length})',
              ),
              icon: const Icon(Icons.check_circle_outline),
            ),
          ],
          selected: {_group},
          onSelectionChanged: (selection) =>
              setState(() => _group = selection.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Buscar cliente',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                widget.payments.isEmpty
                    ? 'No hay cuotas programadas para hoy.'
                    : _group == _TodayDueGroup.pending
                    ? 'No hay pagos pendientes para hoy.'
                    : 'No hay pagos completados para hoy.',
              ),
            ),
          )
        else
          for (final due in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TodayDueTile(
                due: due,
                showContactActions: _group == _TodayDueGroup.pending,
              ),
            ),
      ],
    );
  }
}

class _TodayDueTile extends StatelessWidget {
  const _TodayDueTile({required this.due, required this.showContactActions});

  final TodayDuePayment due;
  final bool showContactActions;

  Future<void> _openContact(
    BuildContext context,
    Future<bool> Function() open,
    String appName,
  ) async {
    final launched = await open();
    if (!context.mounted || launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No se pudo abrir $appName. Verifica el teléfono registrado.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClientAvatar(
                name: due.card.clientName,
                photoPath: due.card.photoPath,
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      due.card.clientName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (due.card.alias?.trim().isNotEmpty ?? false)
                      Text(due.card.alias!),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Abonado: ${CurrencyFormatter.formatGtq(due.paidAmount)} / '
            'Resta: ${CurrencyFormatter.formatGtq(due.remainingAmount)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showContactActions) ...[
                OutlinedButton.icon(
                  onPressed: due.card.primaryPhone?.trim().isNotEmpty ?? false
                      ? () => _openContact(
                          context,
                          () => ContactLauncher.call(due.card.primaryPhone!),
                          'el marcador de llamadas',
                        )
                      : null,
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Llamar'),
                ),
                OutlinedButton.icon(
                  onPressed: due.card.primaryPhone?.trim().isNotEmpty ?? false
                      ? () => _openContact(
                          context,
                          () =>
                              ContactLauncher.whatsApp(due.card.primaryPhone!),
                          'WhatsApp',
                        )
                      : null,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              ],
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CardDetailScreen(cardId: due.card.id),
                  ),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ver tarjeta'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DashboardCardsList extends StatefulWidget {
  const _DashboardCardsList({required this.cards});

  final List<DashboardCard> cards;

  @override
  State<_DashboardCardsList> createState() => _DashboardCardsListState();
}

class _DashboardCardsListState extends State<_DashboardCardsList> {
  final _searchController = TextEditingController();
  String _query = '';

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .trim();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalize(_query);
    final filteredCards = widget.cards
        .where((card) {
          if (query.isEmpty) return true;
          return _normalize(card.clientName).contains(query) ||
              _normalize(card.alias ?? '').contains(query);
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar por cliente o referencia',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (filteredCards.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                widget.cards.isEmpty
                    ? 'No hay tarjetas para este filtro.'
                    : 'No se encontraron tarjetas con esa búsqueda.',
              ),
            ),
          )
        else
          for (final card in filteredCards)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DashboardCardTile(card: card),
            ),
      ],
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
    CardStatus.deactivated => HistoryColors.locked,
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
                itemBuilder: (_) {
                  final availableStatuses = switch (card.status) {
                    CardStatus.debtor => const [CardStatus.deactivated],
                    CardStatus.deactivated => const [CardStatus.active],
                    CardStatus.renewal => const [CardStatus.paid],
                    _ =>
                      CardStatus.values
                          .where(
                            (status) =>
                                status != CardStatus.archived &&
                                status != CardStatus.deactivated &&
                                status != card.status,
                          )
                          .toList(growable: false),
                  };
                  return [
                    for (final status in availableStatuses)
                      PopupMenuItem(value: status, child: Text(status.label)),
                  ];
                },
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
