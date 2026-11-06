import '../../cobros_tarjetas/domain/entities/credit_card.dart';

class DashboardPayment {
  const DashboardPayment({
    required this.scheduledDate,
    required this.updatedAt,
    required this.amountPaid,
  });

  final DateTime scheduledDate;
  final DateTime updatedAt;
  final double amountPaid;
}

class DashboardCard {
  const DashboardCard({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.alias,
    required this.photoPath,
    required this.status,
    required this.weeklyAmount,
    required this.totalInstallments,
    required this.payments,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String? alias;
  final String? photoPath;
  final CardStatus status;
  final double weeklyAmount;
  final int totalInstallments;
  final List<DashboardPayment> payments;

  double get pendingBalance =>
      (weeklyAmount * totalInstallments -
              payments.fold<double>(
                0,
                (sum, payment) => sum + payment.amountPaid,
              ))
          .clamp(0, double.infinity);

  int get remainingInstallments => pendingBalance <= 0.005
      ? 0
      : (pendingBalance / weeklyAmount).ceil().clamp(0, totalInstallments);
}

abstract interface class DashboardRepository {
  Stream<List<DashboardCard>> watchCards();

  /// Validates and persists a status change atomically.
  Future<void> changeStatus(String cardId, CardStatus status);
}
