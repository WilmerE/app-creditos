import 'package:drift/drift.dart';

import '../../../../../core/database/app_database.dart';
import '../../../domain/entities/payment_installment.dart';

class PaymentLocalDataSource {
  const PaymentLocalDataSource(this._database);

  final AppDatabase _database;

  void _validate(PaymentInstallment installment) {
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

  /// Updates only the editable columns of existing installments, atomically.
  /// Throws if any installment does not exist or the receipt is duplicated.
  Future<void> updateInstallments(List<PaymentInstallment> installments) {
    installments.forEach(_validate);
    return _database.transaction(() async {
      for (final installment in installments) {
        final receipt = installment.receiptNumber?.trim();
        final updated =
            await (_database.update(
              _database.payments,
            )..where((row) => row.id.equals(installment.id))).write(
              PaymentsCompanion(
                scheduledDate: Value(installment.scheduledDate),
                amountPaid: Value(installment.amountPaid),
                balanceAfter: Value(installment.balanceAfter),
                paymentType: Value(installment.type.name),
                receiptNumber: Value(
                  receipt == null || receipt.isEmpty ? null : receipt,
                ),
                updatedAt: Value(DateTime.now()),
              ),
            );
        if (updated == 0) {
          throw StateError('La cuota ${installment.id} no existe.');
        }
      }
    });
  }

  Future<void> updateInstallment(PaymentInstallment installment) =>
      updateInstallments([installment]);

  Future<void> savePayments(List<PaymentInstallment> installments) {
    installments.forEach(_validate);
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

  Stream<List<PaymentInstallment>> watchInstallmentsByCard(String cardId) {
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
