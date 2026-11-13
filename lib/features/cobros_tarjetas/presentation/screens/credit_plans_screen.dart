import 'package:flutter/material.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../data/credit_plan_repository.dart';
import '../../domain/entities/credit_plan.dart';

class CreditPlansScreen extends StatefulWidget {
  const CreditPlansScreen({required this.repository, super.key});

  final CreditPlanRepository repository;

  @override
  State<CreditPlansScreen> createState() => _CreditPlansScreenState();
}

class _CreditPlansScreenState extends State<CreditPlansScreen> {
  List<CreditPlan> _plans = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final plans = await widget.repository.getAll();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('No se pudieron cargar los planes: $error');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _edit([CreditPlan? plan]) async {
    final updated = await showDialog<CreditPlan>(
      context: context,
      builder: (_) => _CreditPlanFormDialog(plan: plan),
    );
    if (updated == null) return;
    try {
      await widget.repository.save(updated);
      await _load();
    } on Object catch (error) {
      final message = error.toString().toLowerCase().contains('unique')
          ? 'Ya existe un plan con ese monto y esas condiciones.'
          : 'No se pudo guardar el plan: $error';
      _message(message);
    }
  }

  Future<void> _setActive(CreditPlan plan, bool active) async {
    try {
      await widget.repository.setActive(plan.id!, active);
      await _load();
    } on Object catch (error) {
      _message('No se pudo actualizar el plan: $error');
    }
  }

  Future<void> _delete(CreditPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar plan'),
        content: Text(
          '¿Eliminar el plan de ${CurrencyFormatter.formatGtq(plan.amount)} '
          'con ${plan.installments} cuotas semanales de '
          '${CurrencyFormatter.formatGtq(plan.installmentAmount)}? '
          'Las tarjetas existentes conservarán sus condiciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.delete(plan.id!);
      await _load();
    } on Object catch (error) {
      _message('No se pudo eliminar el plan: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Planes de crédito'),
      actions: [
        IconButton(
          tooltip: 'Crear plan',
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _plans.isEmpty
                  ? const Center(child: Text('No hay planes configurados.'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Los cambios aplican a las tarjetas nuevas. '
                            'Las tarjetas existentes conservan sus cuotas.',
                          ),
                        ),
                        for (final plan in _plans)
                          Card(
                            child: ListTile(
                              leading: Icon(
                                plan.isActive
                                    ? Icons.payments_outlined
                                    : Icons.pause_circle_outline,
                              ),
                              title: Text(
                                '${CurrencyFormatter.formatGtq(plan.amount)} · '
                                '${plan.installments} cuotas',
                              ),
                              subtitle: Text(
                                '${CurrencyFormatter.formatGtq(plan.installmentAmount)} por semana · '
                                'Total ${CurrencyFormatter.formatGtq(plan.total)} · '
                                '${plan.isActive ? 'Activo' : 'Inactivo'}',
                              ),
                              isThreeLine: true,
                              trailing: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 0,
                                children: [
                                  Tooltip(
                                    message: plan.isActive
                                        ? 'Desactivar plan'
                                        : 'Activar plan',
                                    child: Switch(
                                      value: plan.isActive,
                                      onChanged: (value) =>
                                          _setActive(plan, value),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Editar plan',
                                    onPressed: () => _edit(plan),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Eliminar plan',
                                    onPressed: () => _delete(plan),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Nuevo plan'),
    ),
  );
}

class _CreditPlanFormDialog extends StatefulWidget {
  const _CreditPlanFormDialog({this.plan});

  final CreditPlan? plan;

  @override
  State<_CreditPlanFormDialog> createState() => _CreditPlanFormDialogState();
}

class _CreditPlanFormDialogState extends State<_CreditPlanFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.plan?.amount.toStringAsFixed(2) ?? '',
  );
  late final _installments = TextEditingController(
    text: widget.plan?.installments.toString() ?? '',
  );
  late final _installmentAmount = TextEditingController(
    text: widget.plan?.installmentAmount.toStringAsFixed(2) ?? '',
  );
  late bool _active = widget.plan?.isActive ?? true;

  @override
  void dispose() {
    _amount.dispose();
    _installments.dispose();
    _installmentAmount.dispose();
    super.dispose();
  }

  double? _parseMoney(String value) =>
      double.tryParse(value.trim().replaceAll(',', ''));

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CreditPlan(
        id: widget.plan?.id,
        amount: _parseMoney(_amount.text)!,
        installments: int.parse(_installments.text.trim()),
        installmentAmount: _parseMoney(_installmentAmount.text)!,
        isActive: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.plan == null ? 'Crear plan' : 'Editar plan'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto del crédito',
                prefixText: 'Q ',
              ),
              validator: (value) {
                final amount = _parseMoney(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Ingresa un monto mayor que cero.';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _installments,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Número de cuotas semanales',
              ),
              validator: (value) {
                final count = int.tryParse(value?.trim() ?? '');
                if (count == null || count < 1) {
                  return 'Ingresa al menos una cuota.';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _installmentAmount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto de cada cuota',
                prefixText: 'Q ',
              ),
              validator: (value) {
                final amount = _parseMoney(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Ingresa una cuota mayor que cero.';
                }
                final principal = _parseMoney(_amount.text) ?? 0;
                final count = int.tryParse(_installments.text.trim()) ?? 0;
                if (amount * count + 0.005 < principal) {
                  return 'El total de las cuotas debe cubrir el crédito.';
                }
                return null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Plan activo'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}
