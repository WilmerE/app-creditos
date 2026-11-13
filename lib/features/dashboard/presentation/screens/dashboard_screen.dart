import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_seed.dart';
import '../../../../core/network/supabase_delta_sync.dart';
import '../../../../core/network/sync_status_button.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/contact_launcher.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../injection_container.dart';
import '../../../capital_groups/domain/repositories/capital_group_repository.dart';
import '../../../capital_groups/presentation/screens/capital_groups_screen.dart';
import '../../../clientes/presentation/screens/client_list_screen.dart';
import '../../../cobros_tarjetas/presentation/screens/card_navigation.dart';
import '../../../cobros_tarjetas/data/credit_plan_repository.dart';
import '../../../cobros_tarjetas/presentation/screens/credit_plans_screen.dart';
import '../../../clientes/presentation/widgets/client_avatar.dart';
import '../../../cobros_tarjetas/domain/entities/credit_card.dart';
import '../../../cobros_tarjetas/presentation/screens/card_detail_screen.dart';
import '../../../enterprise/presentation/enterprise_config_screen.dart';
import '../../../auth/presentation/screens/account_management_screen.dart';
import '../../data/drift_dashboard_repository.dart';
import '../../data/operational_notifications_local_data_source.dart';
import '../../domain/dashboard_repository.dart';
import '../bloc/dashboard_cubit.dart';

enum _DashboardMenuAction {
  newCard,
  clients,
  enterprise,
  plans,
  account,
  seed,
  signOut,
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => DashboardCubit(
      DriftDashboardRepository(getIt<AppDatabase>()),
      capitalGroupRepository: getIt<CapitalGroupRepository>(),
      database: getIt<AppDatabase>(),
    )..start(),
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
      appBar: AppBar(
        title: const Text('Dashboard de cobros'),
        actions: [
          _OperationalNotificationsButton(
            source: OperationalNotificationsLocalDataSource(
              getIt<AppDatabase>(),
            ),
          ),
          SyncStatusButton(sync: getIt<SupabaseDeltaSync>()),
          PopupMenuButton<_DashboardMenuAction>(
            tooltip: 'Menú de la aplicación',
            onSelected: (action) async {
              switch (action) {
                case _DashboardMenuAction.newCard:
                  await openCardCreation(context);
                case _DashboardMenuAction.clients:
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ClientListScreen(
                        onCreateCard: (client) =>
                            createCardFor(context, client),
                        onOpenCards: (client) =>
                            openClientCards(context, client),
                      ),
                    ),
                  );
                case _DashboardMenuAction.enterprise:
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EnterpriseConfigScreen(),
                    ),
                  );
                case _DashboardMenuAction.plans:
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CreditPlansScreen(
                        repository: getIt<CreditPlanRepository>(),
                      ),
                    ),
                  );
                case _DashboardMenuAction.account:
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AccountManagementScreen(
                        sync: getIt<SupabaseDeltaSync>(),
                      ),
                    ),
                  );
                case _DashboardMenuAction.seed:
                  await _seed(context);
                case _DashboardMenuAction.signOut:
                  await confirmAndSignOut(context, getIt<SupabaseDeltaSync>());
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _DashboardMenuAction.newCard,
                child: ListTile(
                  leading: Icon(Icons.add_card),
                  title: Text('Nueva tarjeta'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _DashboardMenuAction.clients,
                child: ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('Clientes'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _DashboardMenuAction.enterprise,
                child: ListTile(
                  leading: Icon(Icons.business_outlined),
                  title: Text('Configuración empresarial'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _DashboardMenuAction.plans,
                child: ListTile(
                  leading: Icon(Icons.price_change_outlined),
                  title: Text('Planes de crédito'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _DashboardMenuAction.account,
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('Gestionar usuario'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (kDebugMode)
                const PopupMenuItem(
                  value: _DashboardMenuAction.seed,
                  child: ListTile(
                    leading: Icon(Icons.science_outlined),
                    title: Text('Cargar datos de prueba'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _DashboardMenuAction.signOut,
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Cerrar sesión'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
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
                  _CollectionDeadlineBanner(state: state),
                  _UrgentDelinquencySection(state: state),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: state.selectedFolderId ?? 0,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Carpeta de capital',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.folder_outlined),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 0,
                              child: Text('Capital Principal'),
                            ),
                            for (final group in state.capitalGroups)
                              DropdownMenuItem(
                                value: group.id,
                                child: Text(group.name),
                              ),
                          ],
                          onChanged: (value) =>
                              context.read<DashboardCubit>().selectCapitalGroup(
                                value == null || value == 0 ? null : value,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Administrar carpetas de capital',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CapitalGroupsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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

Future<void> _seed(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cargar datos de prueba'),
      content: const Text(
        'Se crearán 80 clientes ficticios y 200 tarjetas en esta base local. '
        'Solo se permite en una base sin clientes, tarjetas ni pagos. '
        'No utilice estos datos para cobros ni contacte los teléfonos de ejemplo.',
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
  if (confirmed != true || !context.mounted) return;
  try {
    final result = await DatabaseSeed(getIt<AppDatabase>()).run();
    if (!context.mounted) return;
    final message = switch (result) {
      DatabaseSeedResult.inserted =>
        'Se cargaron 80 clientes y 200 tarjetas de prueba.',
      DatabaseSeedResult.alreadyInserted =>
        'Los datos de prueba ya fueron cargados.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se pudieron cargar los datos de prueba: $error'),
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

class _UrgentDelinquencySection extends StatelessWidget {
  const _UrgentDelinquencySection({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final urgent = state.selectedCapitalCards
        .where(
          (card) =>
              card.overdueDays >= 30 &&
              card.status != CardStatus.paid &&
              card.status != CardStatus.deactivated,
        )
        .toList(growable: false);
    if (urgent.isEmpty) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFFFFF0E8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seguimiento urgente · mora de 30+ días (${urgent.length})',
              style: const TextStyle(
                color: Colors.deepOrange,
                fontWeight: FontWeight.bold,
              ),
            ),
            for (final card in urgent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.priority_high,
                  color: Colors.deepOrange,
                ),
                title: Text(card.clientName),
                subtitle: Text(
                  '${card.overdueDays} días · Capital pendiente: ${CurrencyFormatter.formatGtq(card.capitalPending)}',
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CardDetailScreen(cardId: card.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OperationalNotificationsButton extends StatelessWidget {
  const _OperationalNotificationsButton({required this.source});

  final OperationalNotificationsLocalDataSource source;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: source.watchUnreadCount(),
    builder: (context, snapshot) {
      final unreadCount = snapshot.data ?? 0;
      return IconButton(
        tooltip: unreadCount == 0
            ? 'Notificaciones'
            : 'Notificaciones sin leer: $unreadCount',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _OperationalNotificationsDialog(source: source),
        ),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_outlined),
            if (unreadCount > 0)
              Positioned(
                top: -7,
                right: -8,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _OperationalNotificationsDialog extends StatefulWidget {
  const _OperationalNotificationsDialog({required this.source});

  final OperationalNotificationsLocalDataSource source;

  @override
  State<_OperationalNotificationsDialog> createState() =>
      _OperationalNotificationsDialogState();
}

class _OperationalNotificationsDialogState
    extends State<_OperationalNotificationsDialog> {
  bool _unreadOnly = false;
  final _listController = ScrollController();

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} · $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final height = (screenSize.height * 0.72).clamp(320.0, 680.0).toDouble();
    final width = (screenSize.width - 48).clamp(280.0, 620.0).toDouble();
    return Dialog(
      child: SizedBox(
        width: width,
        height: height,
        child: StreamBuilder<List<OperationalNotificationRow>>(
          stream: widget.source.watchAll(),
          builder: (context, snapshot) {
            final notifications = snapshot.data ?? const [];
            final unreadCount = notifications.where((item) => !item.isRead).length;
            final visible = _unreadOnly
                ? notifications.where((item) => !item.isRead).toList()
                : notifications;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notificaciones',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('$unreadCount sin leer'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: unreadCount == 0
                            ? null
                            : widget.source.markAllRead,
                        icon: const Icon(Icons.done_all),
                        label: const Text('Marcar todas como leídas'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Todas')),
                      ButtonSegment(value: true, label: Text('No leídas')),
                    ],
                    selected: {_unreadOnly},
                    onSelectionChanged: (selection) => setState(
                      () => _unreadOnly = selection.single,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: snapshot.hasError
                      ? const Center(
                          child: Text('No se pudieron cargar las notificaciones.'),
                        )
                      : visible.isEmpty
                      ? Center(
                          child: Text(
                            _unreadOnly
                                ? 'No tienes notificaciones sin leer.'
                                : 'Todavía no tienes notificaciones.',
                          ),
                        )
                      : Scrollbar(
                          controller: _listController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _listController,
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final notification = visible[index];
                              final urgent =
                                  notification.type == 'urgent_delinquency';
                              return ListTile(
                                tileColor: notification.isRead
                                    ? null
                                    : Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer
                                          .withValues(alpha: 0.35),
                                leading: Icon(
                                  urgent
                                      ? Icons.priority_high
                                      : notification.type == 'mora_day'
                                      ? Icons.warning_amber
                                      : Icons.notifications_active_outlined,
                                  color: urgent
                                      ? Colors.deepOrange
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(notification.title),
                                subtitle: Text(
                                  '${notification.message}\n${_formatDate(notification.createdAt)}',
                                ),
                                isThreeLine: true,
                                trailing: notification.isRead
                                    ? const Tooltip(
                                        message: 'Leída',
                                        child: Icon(Icons.done, size: 20),
                                      )
                                    : IconButton(
                                        tooltip: 'Marcar como leída',
                                        onPressed: () => widget.source.markRead(
                                          notification.id,
                                        ),
                                        icon: const Icon(
                                          Icons.mark_email_read_outlined,
                                        ),
                                      ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CollectionDeadlineBanner extends StatelessWidget {
  const _CollectionDeadlineBanner({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final db = getIt<AppDatabase>();
    return StreamBuilder(
      stream: (db.select(
        db.enterpriseConfigs,
      )..where((row) => row.id.equals(1))).watchSingleOrNull(),
      builder: (context, snapshot) {
        final config = snapshot.data;
        final now = DateTime.now();
        final deadline = DateTime(
          now.year,
          now.month,
          now.day,
          config?.collectionDeadlineHour ?? 18,
          config?.collectionDeadlineMinute ?? 0,
        );
        final remaining = deadline.difference(now);
        final reminder = config?.collectionReminderMinutes ?? 60;
        if (state.pendingDueTodayCount == 0 ||
            remaining.isNegative ||
            remaining.inMinutes > reminder) {
          return const SizedBox.shrink();
        }
        return Card(
          color: const Color(0xFFFFF3CD),
          child: ListTile(
            leading: const Icon(Icons.schedule, color: Colors.deepOrange),
            title: const Text(
              'Se acerca el límite de cobro',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${state.pendingDueTodayCount} cuota(s) de hoy siguen pendientes. Límite: ${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}. Revisa Cobros de hoy para contactar a los clientes.',
            ),
            onTap: () => context.read<DashboardCubit>().selectFilter(
              DashboardFilter.todayDue,
            ),
          ),
        );
      },
    );
  }
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
