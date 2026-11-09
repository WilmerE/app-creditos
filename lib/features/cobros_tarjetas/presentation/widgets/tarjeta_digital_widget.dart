import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../enterprise/domain/enterprise_config.dart';
import '../../domain/entities/credit_card.dart';
import '../../domain/entities/payment_installment.dart';

const Color _wineColor = Color(0xFF800020);
const double _maxCardWidth = 960;
const double _compactBreakpoint = 600;

class _CardMetrics {
  const _CardMetrics({required this.compact, required this.touch});

  final bool compact;
  final bool touch;

  double get cellFont => touch ? 15 : 12;
  double get smallFont => touch ? 13 : 10;
  double get rowHeight => touch ? 52 : 38;
  double get cellPadding => touch ? 14 : 9;
  double get avatarRadius => compact ? 34 : 42;
}

class TarjetaCustomerInfo {
  const TarjetaCustomerInfo({
    required this.name,
    required this.address,
    required this.phone,
    required this.dpi,
    required this.reference,
    required this.startDate,
    required this.requestedAmount,
    required this.paymentPlan,
    this.photo,
  });

  final String name;
  final String address;
  final String phone;
  final String dpi;
  final String reference;
  final DateTime startDate;
  final double requestedAmount;
  final String paymentPlan;
  final ImageProvider<Object>? photo;
}

class TarjetaDigitalWidget extends StatefulWidget {
  const TarjetaDigitalWidget({
    required this.customer,
    required this.initialBalance,
    required this.payments,
    required this.onAutoSave,
    this.onAddRow,
    this.onDeleteRow,
    this.weeklyAmount,
    this.capitalPending,
    this.lateFee,
    this.enterpriseConfig = const EnterpriseConfig(),
    this.renewalColor = const Color(0xFFFFF1D6),
    this.debounceDuration = const Duration(milliseconds: 500),
    super.key,
  });

  final TarjetaCustomerInfo customer;
  final double initialBalance;
  final List<PaymentInstallment> payments;
  final Future<void> Function(List<PaymentInstallment> payments) onAutoSave;
  final Future<void> Function()? onAddRow;
  final Future<void> Function(String id)? onDeleteRow;
  final double? weeklyAmount;
  final double? capitalPending;
  final LateFee? lateFee;
  final EnterpriseConfig enterpriseConfig;
  final Color renewalColor;
  final Duration debounceDuration;

  @override
  State<TarjetaDigitalWidget> createState() => _TarjetaDigitalWidgetState();
}

class _TarjetaDigitalWidgetState extends State<TarjetaDigitalWidget> {
  late List<PaymentInstallment> _payments;
  final Map<String, int> _unconfirmedPayments = {};
  final Set<String> _dirtyCells = {};
  bool _changingRows = false;
  int _saveRevision = 0;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _payments = List.of(widget.payments);
    _recalculateBalances();
    _scheduleLockUpdate();
  }

  @override
  void didUpdateWidget(covariant TarjetaDigitalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.payments, widget.payments) ||
        oldWidget.initialBalance != widget.initialBalance) {
      _payments = List.of(widget.payments);
      _recalculateBalances();
      _scheduleLockUpdate();
    }
  }

  void _scheduleLockUpdate() {
    _lockTimer?.cancel();
    final now = DateTime.now();
    DateTime? next;
    for (final payment in _payments) {
      final createdAt = payment.createdAt;
      if (createdAt == null) continue;
      final expiry = createdAt.add(const Duration(hours: 24));
      if (expiry.isAfter(now) && (next == null || expiry.isBefore(next))) {
        next = expiry;
      }
    }
    if (next != null) {
      _lockTimer = Timer(next.difference(now), () {
        if (!mounted) return;
        setState(_scheduleLockUpdate);
      });
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  void _recalculateBalances() {
    var balance = widget.initialBalance;
    for (var index = 0; index < _payments.length; index++) {
      final payment = _payments[index];
      balance = (balance - payment.principalPaid)
          .clamp(0, double.infinity)
          .toDouble();
      _payments[index] = payment.copyWith(balanceAfter: balance);
    }
  }

  Future<void> _updatePayment(
    int index,
    PaymentInstallment changedPayment,
  ) async {
    final before = List<PaymentInstallment>.of(_payments);
    setState(() {
      if (widget.lateFee != null && widget.capitalPending != null) {
        _payments[index] = changedPayment.copyWith(
          balanceAfter: before[index].balanceAfter,
        );
      } else {
        _payments[index] = changedPayment;
        _recalculateBalances();
      }
    });

    final changedPayments = <PaymentInstallment>[];
    for (var current = index; current < _payments.length; current++) {
      if (!_samePayment(before[current], _payments[current])) {
        changedPayments.add(_payments[current]);
      }
    }
    if (changedPayments.isEmpty) return;

    final revision = ++_saveRevision;
    setState(() => _unconfirmedPayments[changedPayment.id] = revision);

    if (changedPayment.type != PaymentType.cash &&
        (changedPayment.receiptNumber == null ||
            changedPayment.receiptNumber!.trim().isEmpty)) {
      setState(() {
        _payments = before;
        _unconfirmedPayments.remove(changedPayment.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingrese el número de boleta para depósito o transferencia.',
          ),
        ),
      );
      throw StateError(
        'Ingrese el número de boleta para depósito o transferencia.',
      );
    }

    try {
      await widget.onAutoSave(changedPayments);
      if (mounted && _unconfirmedPayments[changedPayment.id] == revision) {
        setState(() => _unconfirmedPayments.remove(changedPayment.id));
      }
    } catch (error) {
      if (!mounted) rethrow;
      if (_unconfirmedPayments[changedPayment.id] == revision) {
        setState(() {
          _payments = before;
          _unconfirmedPayments.remove(changedPayment.id);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el pago localmente: $error'),
          backgroundColor: HistoryColors.overdue,
        ),
      );
      rethrow;
    }
  }

  bool _samePayment(PaymentInstallment first, PaymentInstallment second) {
    return first.scheduledDate == second.scheduledDate &&
        first.amountPaid == second.amountPaid &&
        first.balanceAfter == second.balanceAfter &&
        first.type == second.type &&
        first.receiptNumber == second.receiptNumber;
  }

  Future<void> _changeRows(Future<void> Function() action) async {
    setState(() => _changingRows = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo modificar la fila: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingRows = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final touch =
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.fuchsia;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxCardWidth),
        child: Card(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final metrics = _CardMetrics(
                compact: constraints.maxWidth < _compactBreakpoint,
                touch: touch,
              );
              return Padding(
                padding: EdgeInsets.all(metrics.compact ? 10 : 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CardHeader(
                      customer: widget.customer,
                      metrics: metrics,
                      enterprise: widget.enterpriseConfig,
                    ),
                    const SizedBox(height: 16),
                    if (widget.capitalPending != null && widget.lateFee != null)
                      _BalanceSummary(
                        capital: widget.capitalPending!,
                        lateFee: widget.lateFee!,
                      ),
                    _buildPaymentTable(metrics),
                    if (widget.onAddRow != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed:
                              _changingRows ||
                                  _dirtyCells.isNotEmpty ||
                                  _unconfirmedPayments.isNotEmpty
                              ? null
                              : () => _changeRows(widget.onAddRow!),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar fila'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'NOTA: En caso de incumplimiento se aplicara un recargo de Q. ${widget.enterpriseConfig.mora.toStringAsFixed(2)} diarios sobre saldo',
                      style: TextStyle(
                        color: _wineColor,
                        fontSize: metrics.smallFont + 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentTable(_CardMetrics metrics) {
    return Table(
      columnWidths: {
        0: const FlexColumnWidth(1.2),
        1: FlexColumnWidth(metrics.compact ? 1.3 : 1),
        2: const FlexColumnWidth(1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder.all(color: const Color(0xFFE0E0E0), width: 0.6),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _wineColor),
          children: ['FECHA', 'ABONO', 'RESTA']
              .map(
                (label) => Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: metrics.cellPadding,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.cellFont - 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        for (var index = 0; index < _payments.length; index++)
          _paymentRow(_payments[index], index, metrics),
      ],
    );
  }

  TableRow _paymentRow(
    PaymentInstallment payment,
    int index,
    _CardMetrics metrics,
  ) {
    final locked =
        (payment.createdAt == null && payment.amountPaid > 0) ||
        (payment.createdAt != null &&
            !DateTime.now().isBefore(
              payment.createdAt!.add(const Duration(hours: 24)),
            ));
    final previousBalance = index == 0
        ? widget.initialBalance
        : _payments[index - 1].balanceAfter;
    final settled =
        !_unconfirmedPayments.containsKey(payment.id) &&
        payment.principalPaid > 0 &&
        (payment.balanceAfter <= 0 ||
            (widget.weeklyAmount != null &&
                payment.principalPaid >= widget.weeklyAmount!));
    final canDelete =
        payment.isManual &&
        index == _payments.length - 1 &&
        payment.scheduledDate == null &&
        payment.amountPaid == 0 &&
        payment.createdAt == null &&
        payment.type == PaymentType.cash &&
        payment.receiptNumber == null;
    return TableRow(
      decoration: BoxDecoration(
        color: payment.isRenewal ? widget.renewalColor : Colors.transparent,
      ),
      children: [
        Column(
          children: [
            Text(
              payment.isManual ? 'Manual' : 'Plan original',
              style: TextStyle(
                fontSize: metrics.smallFont,
                color: Colors.grey[700],
              ),
            ),
            if (locked)
              Tooltip(
                message: payment.createdAt == null
                    ? 'Edición bloqueada: falta fecha de registro'
                    : 'Edición bloqueada después de 24 horas',
                child: const Icon(Icons.lock_outline, size: 14),
              ),
            _EditablePaymentCell(
              key: ValueKey('${payment.id}-date'),
              payment: payment,
              previousBalance: previousBalance,
              kind: _EditableCellKind.date,
              metrics: metrics,
              debounceDuration: widget.debounceDuration,
              locked: locked,
              capitalPending: widget.capitalPending,
              lateFee: widget.lateFee,
              onDirty: (dirty) => setState(() {
                if (dirty) {
                  _dirtyCells.add('${payment.id}-date');
                } else {
                  _dirtyCells.remove('${payment.id}-date');
                }
              }),
              onSave: (updated) => _updatePayment(index, updated),
            ),
          ],
        ),
        _EditablePaymentCell(
          key: ValueKey('${payment.id}-amount'),
          payment: payment,
          previousBalance: previousBalance,
          kind: _EditableCellKind.amount,
          metrics: metrics,
          debounceDuration: widget.debounceDuration,
          locked: locked,
          capitalPending: widget.capitalPending,
          lateFee: widget.lateFee,
          onDirty: (dirty) => setState(() {
            if (dirty) {
              _dirtyCells.add('${payment.id}-amount');
            } else {
              _dirtyCells.remove('${payment.id}-amount');
            }
          }),
          onSave: (updated) => _updatePayment(index, updated),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      CurrencyFormatter.formatGtq(payment.balanceAfter),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: metrics.cellFont,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (settled)
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 18,
                      semanticLabel: 'Cuota saldada',
                    ),
                ],
              ),
              if (payment.amountPaid > 0 && payment.createdAt != null)
                Text(
                  '${payment.createdAtEstimated ? 'Estimada: ' : 'Recibido: '}${DateFormat('dd/MM/yyyy HH:mm:ss').format(payment.createdAt!.toLocal())}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: metrics.smallFont,
                    color: Colors.grey[700],
                  ),
                ),
              if (payment.isManual &&
                  index == _payments.length - 1 &&
                  widget.onDeleteRow != null)
                IconButton(
                  tooltip: 'Eliminar última fila vacía',
                  onPressed:
                      !canDelete ||
                          _changingRows ||
                          _dirtyCells.isNotEmpty ||
                          _unconfirmedPayments.isNotEmpty
                      ? null
                      : () =>
                            _changeRows(() => widget.onDeleteRow!(payment.id)),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({required this.capital, required this.lateFee});

  final double capital;
  final LateFee lateFee;

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Días de mora pendientes'),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final date in lateFee.dates)
                ListTile(title: Text(DateFormat('dd/MM/yyyy').format(date))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lateFee.days > 0 && lateFee.dueDate != null)
            InkWell(
              onTap: lateFee.dates.isEmpty ? null : () => _showDetails(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: HistoryColors.overdue),
                ),
                child: Text(
                  'Atraso: ${lateFee.days} días · Mora acumulada: '
                  '${CurrencyFormatter.formatGtq(lateFee.amount)} '
                  '(${CurrencyFormatter.formatGtq(lateFee.rate.toDouble())} diarios desde '
                  '${DateFormat('dd/MM/yyyy').format(lateFee.dueDate!)})',
                  style: const TextStyle(
                    color: HistoryColors.overdue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (lateFee.dates.isNotEmpty)
            TextButton(
              onPressed: () => _showDetails(context),
              child: const Text('Ver días de atraso'),
            ),
          const SizedBox(height: 8),
          Text(
            'Capital pendiente: ${CurrencyFormatter.formatGtq(capital)} + '
            'Mora acumulada: ${CurrencyFormatter.formatGtq(lateFee.amount)} = '
            'Total a pagar hoy: ${CurrencyFormatter.formatGtq(capital + lateFee.amount)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.customer,
    required this.metrics,
    required this.enterprise,
  });

  final TarjetaCustomerInfo customer;
  final _CardMetrics metrics;
  final EnterpriseConfig enterprise;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final avatar = CircleAvatar(
      radius: metrics.avatarRadius,
      foregroundImage: customer.photo,
      backgroundColor: const Color(0xFFEDE7E9),
      child: customer.photo == null
          ? Icon(Icons.person, size: metrics.avatarRadius, color: _wineColor)
          : null,
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          enterprise.name,
          style: TextStyle(
            color: _wineColor,
            fontSize: metrics.compact ? 18 : 21,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
        if (enterprise.showPhone && enterprise.phone.trim().isNotEmpty)
          _HeaderField(
            label: 'Teléfono empresa',
            value: enterprise.phone,
            metrics: metrics,
          ),
        if (enterprise.showNit && enterprise.nit.trim().isNotEmpty)
          _HeaderField(label: 'NIT', value: enterprise.nit, metrics: metrics),
        if (enterprise.showEmail && enterprise.email.trim().isNotEmpty)
          _HeaderField(
            label: 'Correo',
            value: enterprise.email,
            metrics: metrics,
          ),
        if (enterprise.showBankAccount &&
            enterprise.bankAccount.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _wineColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Cuenta bancaria: ${enterprise.bankAccount}',
              style: TextStyle(
                fontSize: metrics.smallFont + 1,
                fontWeight: FontWeight.bold,
                color: _wineColor,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('Inicio: ${dateFormat.format(customer.startDate)}'),
        const SizedBox(height: 6),
        _HeaderField(label: 'Nombre', value: customer.name, metrics: metrics),
        _HeaderField(
          label: 'Dirección',
          value: customer.address,
          metrics: metrics,
        ),
        _HeaderField(
          label: 'Teléfono',
          value: customer.phone,
          metrics: metrics,
        ),
        _HeaderField(label: 'DPI', value: customer.dpi, metrics: metrics),
        _HeaderField(
          label: 'Referencia / Alias',
          value: customer.reference,
          metrics: metrics,
        ),
        const SizedBox(height: 4),
        Text(
          'Solicitado: ${CurrencyFormatter.formatGtq(customer.requestedAmount)}'
          '   |   Plan: ${customer.paymentPlan}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(metrics.compact ? 10 : 14),
      decoration: BoxDecoration(
        border: Border.all(color: _wineColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: metrics.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerRight, child: avatar),
                info,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                avatar,
              ],
            ),
    );
  }
}

class _HeaderField extends StatelessWidget {
  const _HeaderField({
    required this.label,
    required this.value,
    required this.metrics,
  });

  final String label;
  final String value;
  final _CardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: metrics.smallFont + 1,
            color: Colors.black87,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

enum _EditableCellKind { date, amount }

class _EditablePaymentCell extends StatefulWidget {
  const _EditablePaymentCell({
    required this.payment,
    required this.previousBalance,
    required this.kind,
    required this.metrics,
    required this.debounceDuration,
    required this.onSave,
    required this.onDirty,
    required this.locked,
    required this.capitalPending,
    required this.lateFee,
    super.key,
  });

  final PaymentInstallment payment;
  final double previousBalance;
  final _EditableCellKind kind;
  final _CardMetrics metrics;
  final Duration debounceDuration;
  final Future<void> Function(PaymentInstallment) onSave;
  final ValueChanged<bool> onDirty;
  final bool locked;
  final double? capitalPending;
  final LateFee? lateFee;

  @override
  State<_EditablePaymentCell> createState() => _EditablePaymentCellState();
}

class _EditablePaymentCellState extends State<_EditablePaymentCell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;
  bool _saving = false;
  int _editRevision = 0;
  String? _errorText;

  bool get _isDate => widget.kind == _EditableCellKind.date;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _initialText);
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  String get _initialText => _isDate
      ? widget.payment.scheduledDate == null
            ? ''
            : DateFormat('dd/MM/yyyy').format(widget.payment.scheduledDate!)
      : widget.payment.amountPaid == 0
      ? ''
      : widget.payment.amountPaid.toStringAsFixed(2);

  @override
  void didUpdateWidget(covariant _EditablePaymentCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payment != widget.payment && !_focusNode.hasFocus) {
      _controller.text = _initialText;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _debounce?.cancel();
      _save();
    }
  }

  void _onChanged(String value) {
    _editRevision++;
    widget.onDirty(true);
    _errorText = null;
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, _save);
    setState(() {});
  }

  Future<void> _save() async {
    final updated = _updatedPayment();
    if (updated == null) return;
    if (updated == widget.payment) {
      widget.onDirty(false);
      return;
    }

    await _persist(updated);
  }

  Future<void> _persist(PaymentInstallment payment) async {
    final revision = _editRevision;
    widget.onDirty(true);
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSave(payment);
      if (!mounted) return;
      if (revision == _editRevision) {
        widget.onDirty(false);
        setState(() => _saving = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = 'Error';
      });
    }
  }

  Future<void> _selectManualDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = widget.payment.scheduledDate?.toLocal();
    final initialDate = current == null || current.isBefore(today)
        ? today
        : DateTime(current.year, current.month, current.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(today.year + 100, today.month, today.day),
    );
    if (selected == null || !mounted) return;

    _controller.text = DateFormat('dd/MM/yyyy').format(selected);
    _editRevision++;
    widget.onDirty(true);
    setState(() => _errorText = null);
    await _save();
  }

  PaymentInstallment? _updatedPayment() {
    if (_isDate) {
      if (_controller.text.trim().isEmpty &&
          widget.payment.scheduledDate == null) {
        return widget.payment;
      }
      try {
        final date = DateFormat('dd/MM/yyyy').parseStrict(_controller.text);
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        if (widget.payment.isManual && date.isBefore(todayDate)) {
          setState(() => _errorText = 'La fecha no puede ser anterior a hoy');
          return null;
        }
        return widget.payment.copyWith(
          scheduledDate: date,
          balanceAfter: widget.payment.balanceAfter,
        );
      } on FormatException {
        setState(() => _errorText = 'Fecha inválida');
        return null;
      }
    }

    final amountText = _controller.text.trim().replaceAll(',', '.');
    final double? amount = amountText.isEmpty ? 0 : double.tryParse(amountText);
    if (amount == null || !amount.isFinite || amount < 0) {
      setState(() => _errorText = 'Abono inválido');
      return null;
    }
    if ((amount * 100 - (amount * 100).round()).abs() > 0.00001) {
      setState(() => _errorText = 'Máximo dos decimales');
      return null;
    }
    final fee = widget.lateFee;
    final capital = widget.capitalPending;
    if (fee != null && capital != null) {
      final amountCents = (amount * 100).round();
      final oldCents = (widget.payment.amountPaid * 100).round();
      final delta = amountCents - oldCents;
      final maximum = oldCents + ((capital + fee.amount) * 100).round();
      if (amountCents > maximum) {
        setState(
          () => _errorText = 'Máximo Q${(maximum / 100).toStringAsFixed(2)}',
        );
        return null;
      }
      if (delta > 0 && fee.days > 0) {
        final rate = fee.rate * 100;
        if (rate <= 0) {
          setState(() => _errorText = 'Configure una mora diaria válida');
          return null;
        }
        if (delta < rate) {
          setState(
            () => _errorText =
                'Abono minimo de Q${fee.rate.toStringAsFixed(2)} para cubrir al menos un dia de mora',
          );
          return null;
        }
      }
    }
    final balance = (widget.previousBalance - amount)
        .clamp(0, double.infinity)
        .toDouble();
    return widget.payment.copyWith(amountPaid: amount, balanceAfter: balance);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: metrics.rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextFormField(
              readOnly: widget.locked,
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              keyboardType: _isDate
                  ? TextInputType.datetime
                  : const TextInputType.numberWithOptions(decimal: true),
              textAlign: _isDate ? TextAlign.center : TextAlign.right,
              style: TextStyle(fontSize: metrics.cellFont),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: metrics.touch ? 12 : 8,
                ),
                border: InputBorder.none,
                errorText: _errorText,
                errorStyle: TextStyle(fontSize: metrics.smallFont - 2),
                suffixIcon: _saving
                    ? const Padding(
                        padding: EdgeInsets.all(7),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      )
                    : _isDate &&
                          widget.payment.isManual &&
                          !widget.locked
                    ? IconButton(
                        tooltip: 'Seleccionar fecha',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.calendar_today, size: 16),
                        onPressed: _selectManualDate,
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
              ),
            ),
            if (!_isDate) ...[
              DropdownButtonFormField<PaymentType>(
                initialValue: widget.payment.type,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: metrics.touch ? 8 : 2,
                  ),
                ),
                style: TextStyle(
                  fontSize: metrics.smallFont,
                  color: Colors.black87,
                ),
                items: PaymentType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: widget.locked
                    ? null
                    : (type) {
                        if (type == null) return;
                        final receipt = type == PaymentType.cash
                            ? null
                            : widget.payment.receiptNumber;
                        _persist(
                          widget.payment.copyWith(
                            type: type,
                            receiptNumber: receipt,
                            clearReceiptNumber: type == PaymentType.cash,
                          ),
                        );
                      },
              ),
              if (widget.payment.type != PaymentType.cash)
                TextFormField(
                  key: ValueKey('${widget.payment.id}-receipt'),
                  readOnly: widget.locked,
                  initialValue: widget.payment.receiptNumber ?? '',
                  onChanged: (value) {
                    _editRevision++;
                    widget.onDirty(true);
                    _debounce?.cancel();
                    _debounce = Timer(widget.debounceDuration, () {
                      final updated = widget.payment.copyWith(
                        receiptNumber: value.trim(),
                        clearReceiptNumber: value.trim().isEmpty,
                      );
                      _persist(updated);
                    });
                  },
                  style: TextStyle(fontSize: metrics.smallFont),
                  decoration: InputDecoration(
                    hintText: 'No. boleta',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: metrics.touch ? 10 : 3,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
