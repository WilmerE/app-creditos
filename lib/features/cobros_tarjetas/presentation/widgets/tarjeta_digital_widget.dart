import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/payment_installment.dart';

const Color _wineColor = Color(0xFF800020);
const double _maxCardWidth = 960;
const double _compactBreakpoint = 600;
const String _latePaymentNote =
    'NOTA: En caso de incumplimiento se aplicara un recargo de Q. 20 diarios sobre saldo';

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
    this.renewalColor = const Color(0xFFFFF1D6),
    this.debounceDuration = const Duration(milliseconds: 500),
    super.key,
  });

  final TarjetaCustomerInfo customer;
  final double initialBalance;
  final List<PaymentInstallment> payments;
  final Future<void> Function(List<PaymentInstallment> payments) onAutoSave;
  final Color renewalColor;
  final Duration debounceDuration;

  @override
  State<TarjetaDigitalWidget> createState() => _TarjetaDigitalWidgetState();
}

class _TarjetaDigitalWidgetState extends State<TarjetaDigitalWidget> {
  late List<PaymentInstallment> _payments;

  @override
  void initState() {
    super.initState();
    _payments = List.of(widget.payments);
    _recalculateBalances();
  }

  @override
  void didUpdateWidget(covariant TarjetaDigitalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.payments, widget.payments) ||
        oldWidget.initialBalance != widget.initialBalance) {
      _payments = List.of(widget.payments);
      _recalculateBalances();
    }
  }

  void _recalculateBalances() {
    var balance = widget.initialBalance;
    for (var index = 0; index < _payments.length; index++) {
      final payment = _payments[index];
      balance = (balance - payment.amountPaid)
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
      _payments[index] = changedPayment;
      _recalculateBalances();
    });

    final changedPayments = <PaymentInstallment>[];
    for (var current = index; current < _payments.length; current++) {
      if (!_samePayment(before[current], _payments[current])) {
        changedPayments.add(_payments[current]);
      }
    }
    if (changedPayments.isEmpty) return;

    if (changedPayment.type != PaymentType.cash &&
        (changedPayment.receiptNumber == null ||
            changedPayment.receiptNumber!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingrese el número de boleta para depósito o transferencia.',
          ),
        ),
      );
      return;
    }

    try {
      await widget.onAutoSave(changedPayments);
    } catch (error) {
      if (!mounted) rethrow;
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
                    _CardHeader(customer: widget.customer, metrics: metrics),
                    const SizedBox(height: 16),
                    _buildPaymentGrid(metrics),
                    const SizedBox(height: 12),
                    Text(
                      _latePaymentNote,
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

  Widget _buildPaymentGrid(_CardMetrics metrics) {
    if (metrics.compact) {
      return _buildPaymentTable(_payments, 0, metrics);
    }
    final splitAt = (_payments.length / 2).ceil();
    final left = _payments.take(splitAt).toList(growable: false);
    final right = _payments.skip(splitAt).toList(growable: false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildPaymentTable(left, 0, metrics)),
        const SizedBox(width: 12),
        Expanded(child: _buildPaymentTable(right, splitAt, metrics)),
      ],
    );
  }

  Widget _buildPaymentTable(
    List<PaymentInstallment> payments,
    int offset,
    _CardMetrics metrics,
  ) {
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
        for (var index = 0; index < payments.length; index++)
          _paymentRow(payments[index], offset + index, metrics),
      ],
    );
  }

  TableRow _paymentRow(
    PaymentInstallment payment,
    int index,
    _CardMetrics metrics,
  ) {
    final previousBalance = index == 0
        ? widget.initialBalance
        : _payments[index - 1].balanceAfter;
    return TableRow(
      decoration: BoxDecoration(
        color: payment.isRenewal ? widget.renewalColor : Colors.transparent,
      ),
      children: [
        _EditablePaymentCell(
          key: ValueKey('${payment.id}-date'),
          payment: payment,
          previousBalance: previousBalance,
          kind: _EditableCellKind.date,
          metrics: metrics,
          debounceDuration: widget.debounceDuration,
          onSave: (updated) => _updatePayment(index, updated),
        ),
        _EditablePaymentCell(
          key: ValueKey('${payment.id}-amount'),
          payment: payment,
          previousBalance: previousBalance,
          kind: _EditableCellKind.amount,
          metrics: metrics,
          debounceDuration: widget.debounceDuration,
          onSave: (updated) => _updatePayment(index, updated),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            CurrencyFormatter.formatGtq(payment.balanceAfter),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: metrics.cellFont,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.customer, required this.metrics});

  final TarjetaCustomerInfo customer;
  final _CardMetrics metrics;

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
          'V&\$ INVERSIONES',
          style: TextStyle(
            color: _wineColor,
            fontSize: metrics.compact ? 18 : 21,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
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
    super.key,
  });

  final PaymentInstallment payment;
  final double previousBalance;
  final _EditableCellKind kind;
  final _CardMetrics metrics;
  final Duration debounceDuration;
  final Future<void> Function(PaymentInstallment) onSave;

  @override
  State<_EditablePaymentCell> createState() => _EditablePaymentCellState();
}

class _EditablePaymentCellState extends State<_EditablePaymentCell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;
  bool _saving = false;
  String? _errorText;

  bool get _isDate => widget.kind == _EditableCellKind.date;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _initialText);
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  String get _initialText => _isDate
      ? DateFormat('dd/MM/yyyy').format(widget.payment.scheduledDate)
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
    _errorText = null;
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, _save);
    setState(() {});
  }

  Future<void> _save() async {
    final updated = _updatedPayment();
    if (updated == null || updated == widget.payment) return;

    await _persist(updated);
  }

  Future<void> _persist(PaymentInstallment payment) async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSave(payment);
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = 'Error';
      });
    }
  }

  PaymentInstallment? _updatedPayment() {
    if (_isDate) {
      try {
        final date = DateFormat('dd/MM/yyyy').parseStrict(_controller.text);
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
                onChanged: (type) {
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
                  initialValue: widget.payment.receiptNumber ?? '',
                  onChanged: (value) {
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
