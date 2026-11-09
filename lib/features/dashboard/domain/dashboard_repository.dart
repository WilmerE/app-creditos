import '../../cobros_tarjetas/domain/entities/credit_card.dart';

class DashboardPayment {
  const DashboardPayment({
    required this.scheduledDate,
    required this.updatedAt,
    required this.amountPaid,
    this.isManual = false,
    this.moraPaid = 0,
  });

  final DateTime? scheduledDate;
  final DateTime updatedAt;
  final double amountPaid;
  final bool isManual;
  final double moraPaid;
}

class DashboardCard {
  const DashboardCard({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.alias,
    required this.photoPath,
    this.primaryPhone,
    required this.status,
    required this.weeklyAmount,
    required this.totalInstallments,
    required this.payments,
    this.outstandingMora = 0,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String? alias;
  final String? photoPath;
  final String? primaryPhone;
  final CardStatus status;
  final double weeklyAmount;
  final int totalInstallments;
  final List<DashboardPayment> payments;
  final double outstandingMora;

  double get pendingBalance =>
      (weeklyAmount * totalInstallments -
              payments.fold<double>(
                0,
                (sum, payment) => sum + payment.amountPaid - payment.moraPaid,
              ))
          .clamp(0, double.infinity) +
      outstandingMora;

  double get capitalPending =>
      (pendingBalance - outstandingMora).clamp(0, double.infinity);

  int get remainingInstallments => capitalPending <= 0.005
      ? 0
      : (capitalPending / weeklyAmount).ceil().clamp(0, totalInstallments);
}

class TodayDuePayment {
  const TodayDuePayment({required this.card, required this.payment});

  final DashboardCard card;
  final DashboardPayment payment;

  /// Amount applied to this installment's capital, excluding late-fee payment.
  double get paidAmount =>
      (payment.amountPaid - payment.moraPaid).clamp(0, card.weeklyAmount);

  double get remainingAmount =>
      (card.weeklyAmount - paidAmount).clamp(0, card.weeklyAmount);

  bool get isPaid => remainingAmount <= 0.005;
}

abstract interface class DashboardRepository {
  Stream<List<DashboardCard>> watchCards();

  /// Validates and persists a status change atomically.
  Future<void> changeStatus(String cardId, CardStatus status);
}
