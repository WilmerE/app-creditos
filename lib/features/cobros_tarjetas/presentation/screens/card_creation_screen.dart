import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../injection_container.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/presentation/widgets/client_avatar.dart';
import '../../../clientes/presentation/widgets/client_photo_picker.dart';
import '../../domain/services/payment_plan_calculator.dart';
import '../bloc/card_creation_cubit.dart';

const cardHistoryColors = <String>[
  '#800020',
  '#1565C0',
  '#2E7D32',
  '#EF6C00',
  '#6A1B9A',
  '#00838F',
  '#F9A825',
  '#455A64',
];

Color colorFromHex(String hex) =>
    Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

class CardCreationScreen extends StatelessWidget {
  const CardCreationScreen({super.key, this.client});

  /// When provided, the client selector and the new/existing switch are skipped.
  final Client? client;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CardCreationCubit>()..start(preselected: client),
      child: CardCreationView(lockedClient: client != null),
    );
  }
}

class CardCreationView extends StatefulWidget {
  const CardCreationView({super.key, required this.lockedClient});

  final bool lockedClient;

  @override
  State<CardCreationView> createState() => CardCreationViewState();
}

class CardCreationViewState extends State<CardCreationView> {
  final _customAmount = TextEditingController();

  @override
  void dispose() {
    _customAmount.dispose();
    super.dispose();
  }

  void _onCustomAmount(String text) {
    final amount = double.tryParse(text.trim().replaceAll(',', ''));
    context.read<CardCreationCubit>().selectAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CardCreationCubit, CardCreationState>(
      listenWhen: (p, c) => p.status != c.status,
      listener: (context, state) {
        if (state.status == CardCreationStatus.success) {
          Navigator.of(context).pop(state.createdCardId);
        } else if (state.status == CardCreationStatus.failure &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.errorMessage!)));
        }
      },
      builder: (context, state) {
        final cubit = context.read<CardCreationCubit>();
        final theme = Theme.of(context);
        final customText = _customAmount.text.trim();
        final unsupportedCustom =
            customText.isNotEmpty &&
            state.amount != null &&
            state.options.isEmpty;

        return Scaffold(
          appBar: AppBar(title: const Text('Nueva tarjeta')),
          body: state.status == CardCreationStatus.loading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!widget.lockedClient) ...[
                          SegmentedButton<ClientMode>(
                            segments: const [
                              ButtonSegment(
                                value: ClientMode.existing,
                                icon: Icon(Icons.people_outline),
                                label: Text('Cliente Existente'),
                              ),
                              ButtonSegment(
                                value: ClientMode.newClient,
                                icon: Icon(Icons.person_add_alt_1_outlined),
                                label: Text('Cliente Nuevo'),
                              ),
                            ],
                            selected: {state.mode},
                            onSelectionChanged: (s) => cubit.setMode(s.first),
                          ),
                          const SizedBox(height: 16),
                        ],
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.topCenter,
                          child: state.mode == ClientMode.newClient
                              ? _NewClientForm(
                                  draft: state.draft,
                                  onChanged: cubit.updateDraft,
                                )
                              : widget.lockedClient
                              ? const SizedBox.shrink()
                              : _ExistingClientSelector(state: state),
                        ),
                        const SizedBox(height: 12),
                        _ClientHeaderPreview(
                          state: state,
                          color: colorFromHex(state.colorHex),
                        ),
                        if (state.mode == ClientMode.existing &&
                            state.renewalBlocked) ...[
                          const SizedBox(height: 12),
                          Material(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      CardCreationCubit.lockMessage,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Monto del crédito',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final amount
                                in PaymentPlanCalculator.quickAmounts)
                              ChoiceChip(
                                label: Text(
                                  CurrencyFormatter.formatGtq(amount),
                                ),
                                selected:
                                    state.amount == amount &&
                                    _customAmount.text.isEmpty,
                                onSelected: (_) {
                                  _customAmount.clear();
                                  cubit.selectAmount(amount);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customAmount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: _onCustomAmount,
                          decoration: InputDecoration(
                            labelText: 'Monto personalizado',
                            prefixText: 'Q ',
                            border: const OutlineInputBorder(),
                            errorText: unsupportedCustom
                                ? 'Sin plan para este monto (use 500, 1,000, 1,500, 2,000 o múltiplos de 250 superiores a 2,000)'
                                : null,
                            errorMaxLines: 3,
                          ),
                        ),
                        if (state.options.length > 1) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Plan de pagos',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<PlanOption>(
                            segments: [
                              for (final option in state.options)
                                ButtonSegment(
                                  value: option,
                                  label: Text(
                                    '${option.installments} x ${CurrencyFormatter.formatGtq(option.installmentAmount)}',
                                  ),
                                ),
                            ],
                            selected: {?state.option},
                            onSelectionChanged: (s) =>
                                cubit.selectOption(s.first),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Color del historial',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            for (final hex in cardHistoryColors)
                              _ColorDot(
                                color: colorFromHex(hex),
                                selected: state.colorHex == hex,
                                onTap: () => cubit.selectColor(hex),
                              ),
                          ],
                        ),
                        if (state.plan != null) ...[
                          const SizedBox(height: 24),
                          _PlanPreview(
                            plan: state.plan!,
                            color: colorFromHex(state.colorHex),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: state.canSubmit ? cubit.submit : null,
                          icon: state.status == CardCreationStatus.saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Crear tarjeta'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _ExistingClientSelector extends StatefulWidget {
  const _ExistingClientSelector({required this.state});

  final CardCreationState state;

  @override
  State<_ExistingClientSelector> createState() =>
      _ExistingClientSelectorState();
}

class _ExistingClientSelectorState extends State<_ExistingClientSelector> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CardCreationCubit>();
    final state = widget.state;
    final theme = Theme.of(context);
    final clients = state.visibleClients;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          onChanged: cubit.setQuery,
          decoration: const InputDecoration(
            labelText: 'Buscar cliente (nombre, alias o DPI)',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              ClientCardFilter.all: 'Todos',
              ClientCardFilter.eligible: 'Sin tarjeta activa',
              ClientCardFilter.withActiveCard: 'Con tarjeta activa',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: state.filter == entry.key,
                onSelected: (_) => cubit.setFilter(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: clients.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay clientes que coincidan.'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: clients.length,
                  itemBuilder: (context, i) {
                    final client = clients[i];
                    final hasActive = state.hasActiveCard(client);
                    return ListTile(
                      selected: state.client?.id == client.id,
                      leading: ClientAvatar(
                        name: client.fullName,
                        photoPath: client.photoPath,
                        radius: 20,
                      ),
                      title: Text(
                        client.fullName,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(client.alias ?? ''),
                      trailing: hasActive
                          ? Chip(
                              avatar: Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: theme.colorScheme.error,
                              ),
                              label: const Text('Tarjeta activa'),
                            )
                          : const Chip(
                              avatar: Icon(
                                Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: Text('Apto'),
                            ),
                      onTap: () => cubit.selectClient(client),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NewClientForm extends StatefulWidget {
  const _NewClientForm({required this.draft, required this.onChanged});

  final NewClientDraft draft;
  final ValueChanged<NewClientDraft> onChanged;

  @override
  State<_NewClientForm> createState() => _NewClientFormState();
}

class _NewClientFormState extends State<_NewClientForm> {
  late NewClientDraft _draft = widget.draft;

  void _update(NewClientDraft draft) {
    setState(() => _draft = draft);
    widget.onChanged(draft);
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClientPhotoPicker(
          name: _draft.name,
          pendingPhotoPath: _draft.photoPath,
          size: 96,
          onPicked: (path) => _update(_draft.copyWith(photoPath: () => path)),
          onRemoved: () => _update(_draft.copyWith(photoPath: () => null)),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: _draft.name,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Nombre completo *'),
          onChanged: (v) => _update(_draft.copyWith(name: v)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _draft.address,
          textCapitalization: TextCapitalization.sentences,
          decoration: _decoration('Dirección / Ubicación *'),
          onChanged: (v) => _update(_draft.copyWith(address: v)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _draft.phone,
          keyboardType: TextInputType.phone,
          decoration: _decoration('Teléfono'),
          onChanged: (v) => _update(_draft.copyWith(phone: v)),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (_) => _draft.phoneValid ? null : 'Número no válido',
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _draft.dpi,
          keyboardType: TextInputType.number,
          decoration: _decoration('DPI / Documento'),
          onChanged: (v) => _update(_draft.copyWith(dpi: v)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _draft.alias,
          textCapitalization: TextCapitalization.characters,
          decoration: _decoration(
            'Referencia / Alias',
            hint: 'YOLI DE DON NERY',
          ),
          onChanged: (v) => _update(_draft.copyWith(alias: v)),
        ),
      ],
    );
  }
}

/// Header of the digital card showing the basic data of the chosen client.
class _ClientHeaderPreview extends StatelessWidget {
  const _ClientHeaderPreview({required this.state, required this.color});

  final CardCreationState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isNew = state.mode == ClientMode.newClient;
    final client = state.client;
    final String name;
    final String? alias;
    final String? phone;
    final String address;
    if (isNew) {
      name = state.draft.name.trim();
      alias = state.draft.alias.trim();
      phone = state.draft.phone.trim();
      address = state.draft.address.trim();
    } else {
      name = client?.fullName ?? '';
      alias = client?.alias;
      phone = client?.primaryPhone;
      address = client?.address ?? '';
    }
    final style = const TextStyle(color: Colors.white);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? 'Nombre del cliente' : name,
            style: style.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (alias != null && alias.isNotEmpty) Text(alias, style: style),
          if (address.isNotEmpty) Text(address, style: style),
          if (phone != null && phone.isNotEmpty)
            Text('Tel. $phone', style: style),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black87 : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({required this.plan, required this.color});

  final PaymentPlan plan;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final headerStyle = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total a pagar: ${CurrencyFormatter.formatGtq(plan.total)} · '
          'Inicia ${dateFormat.format(plan.startDate)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Table(
          border: TableBorder.all(color: Colors.black26),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF800020)),
              children: [
                for (final title in const ['FECHA', 'ABONO', 'RESTA'])
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(title, style: headerStyle),
                  ),
              ],
            ),
            for (var i = 0; i < plan.installments.length; i++)
              TableRow(
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12)),
                children: [
                  _cell(dateFormat.format(plan.installments[i].scheduledDate)),
                  _cell(
                    CurrencyFormatter.formatGtq(plan.option.installmentAmount),
                  ),
                  _cell(CurrencyFormatter.formatGtq(plan.projectedBalance(i))),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _cell(String text) =>
      Padding(padding: const EdgeInsets.all(8), child: Text(text));
}
