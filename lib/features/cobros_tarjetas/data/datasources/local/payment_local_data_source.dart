import 'package:drift/drift.dart';

import '../../../../../core/database/app_database.dart';
import '../../../domain/entities/payment_installment.dart';

class PaymentLocalDataSource {
  const PaymentLocalDataSource(this._database);

  final AppDatabase _database;

  Future<void> savePayments(List<PaymentInstallment> installments) {
    for (final installment in installments) {
      if (installment.type != PaymentType.cash &&
          (installment.receiptNumber == null ||
              installment.receiptNumber!.trim().isEmpty)) {
        throw ArgumentError.value(
          installment.id,
          'installment',
          'Los pagos por depósito o transferencia requieren número de boleta.',
        );
      }
    }
    final companions = installments
        .map((installment) {
          return PaymentsCompanion.insert(
            id: installment.id,
            cardId: Value(installment.cardId),
            scheduledDate: installment.scheduledDate,
            amountPaid: Value(installment.amountPaid),
            balanceAfter: installment.balanceAfter,
            paymentType: Value(installment.type.name),
            receiptNumber: Value(installment.receiptNumber),
            isRenewal: Value(installment.isRenewal),
          );
        })
        .toList(growable: false);

    return _database.savePayments(companions);
  }

  Stream<List<PaymentInstallment>> watchPayments(String cardId) {
    return _database.watchPayments(cardId).map((rows) {
      return rows
          .map(
            (row) => PaymentInstallment(
              id: row.id,
              cardId: row.cardId,
              scheduledDate: row.scheduledDate,
              amountPaid: row.amountPaid,
              balanceAfter: row.balanceAfter,
              type: PaymentType.values.firstWhere(
                (type) => type.name == row.paymentType,
              ),
              receiptNumber: row.receiptNumber,
              isRenewal: row.isRenewal,
            ),
          )
          .toList(growable: false);
    });
  }
}
