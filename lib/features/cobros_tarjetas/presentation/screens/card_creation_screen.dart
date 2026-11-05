import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../injection_container.dart';
import '../../../clientes/domain/entities/client.dart';
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

  /// When provided, the client selector is skipped.
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
                        if (widget.lockedClient)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_outline),
                            title: Text(state.client?.fullName ?? ''),
                            subtitle: Text(state.client?.alias ?? ''),
                          )
                        else
                          DropdownButtonFormField<Client>(
                            initialValue: state.client,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final client in state.clients)
                                DropdownMenuItem(
                                  value: client,
                                  child: Text(
                                    client.fullName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (client) {
                              if (client != null) cubit.selectClient(client);
                            },
                          ),
                        if (state.renewalBlocked) ...[
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
