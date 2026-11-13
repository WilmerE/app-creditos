import 'package:uuid/uuid.dart';

import '../../../../core/utils/date_helpers.dart';
import '../entities/payment_installment.dart';

class InvalidPlanAmountException implements Exception {
  const InvalidPlanAmountException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A selectable combination of number of installments and weekly amount.
class PlanOption {
  const PlanOption(this.installments, this.installmentAmount);

  final int installments;
  final double installmentAmount;

  double get total => installments * installmentAmount;

  @override
  bool operator ==(Object other) =>
      other is PlanOption &&
      other.installments == installments &&
      other.installmentAmount == installmentAmount;

  @override
  int get hashCode => Object.hash(installments, installmentAmount);
}

class PaymentPlan {
  const PaymentPlan({
    required this.requestedAmount,
    required this.option,
    required this.startDate,
    required this.installments,
  });

  final double requestedAmount;
  final PlanOption option;
  final DateTime startDate;

  /// Unpaid installments (`amountPaid` 0); `balanceAfter` is the full debt
  /// until payments are registered, as the editable card recalculates it.
  final List<PaymentInstallment> installments;

  double get total => option.total;

  /// Projected balance after paying installment [index] on schedule.
  double projectedBalance(int index) =>
      total - option.installmentAmount * (index + 1);
}

abstract final class PaymentPlanCalculator {
  static const double _weeklyQuota = 320;
  static const List<double> quickAmounts = [500, 1000, 1500, 2000, 3000, 5000];

  /// Plans available for [amount]; the first one is the default.
  static List<PlanOption> optionsFor(double amount) {
    if (amount == 500) return const [PlanOption(6, 125)];
    if (amount == 1000) {
      return const [PlanOption(4, _weeklyQuota), PlanOption(7, 210)];
    }
    if (amount == 1500) return const [PlanOption(6, _weeklyQuota)];
    if (amount == 2000) return const [PlanOption(8, _weeklyQuota)];
    if (amount > 2000) {
      final weeks = amount / 1000 * 4;
      if (weeks == weeks.roundToDouble()) {
        return [PlanOption(weeks.round(), _weeklyQuota)];
      }
    }
    return const [];
  }

  static bool isSupported(double amount) => optionsFor(amount).isNotEmpty;

  /// Builds a weekly schedule, defaulting to next Monday and its Saturday.
  static PaymentPlan calculate({
    required double requestedAmount,
    required String cardId,
    PlanOption? option,
    List<PlanOption>? availableOptions,
    DateTime? startDate,
    DateTime? firstPaymentDate,
    DateTime? now,
    String Function()? idGenerator,
    bool isRenewal = false,
  }) {
    final options = availableOptions ?? optionsFor(requestedAmount);
    if (options.isEmpty) {
      throw const InvalidPlanAmountException(
        'No existe un plan para el monto solicitado.',
      );
    }
    final selected = option ?? options.first;
    if (!options.contains(selected)) {
      throw const InvalidPlanAmountException(
        'El plan elegido no corresponde al monto solicitado.',
      );
    }

    final start = startDate != null
        ? DateTime(startDate.year, startDate.month, startDate.day)
        : DateHelpers.nextMonday(now ?? DateTime.now());
    final first = firstPaymentDate != null
        ? DateTime(
            firstPaymentDate.year,
            firstPaymentDate.month,
            firstPaymentDate.day,
          )
        : DateTime(start.year, start.month, start.day + 5);
    if (first.isBefore(start)) {
      throw const InvalidPlanAmountException(
        'La fecha del primer pago no puede ser anterior al inicio del crédito.',
      );
    }
    final newId = idGenerator ?? () => const Uuid().v4();

    final installments = [
      for (var i = 0; i < selected.installments; i++)
        PaymentInstallment(
          id: newId(),
          cardId: cardId,
          scheduledDate: DateTime(first.year, first.month, first.day + 7 * i),
          amountPaid: 0,
          balanceAfter: selected.total,
          isRenewal: isRenewal,
        ),
    ];

    return PaymentPlan(
      requestedAmount: requestedAmount,
      option: selected,
      startDate: start,
      installments: installments,
    );
  }
}
