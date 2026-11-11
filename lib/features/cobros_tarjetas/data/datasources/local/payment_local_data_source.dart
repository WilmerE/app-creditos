import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/app_database.dart';
import '../../../domain/entities/credit_card.dart';
import '../../../domain/entities/payment_installment.dart';
import 'mora_local_data_source.dart';
import '../../../../dashboard/data/operational_notifications_local_data_source.dart';

class PaymentLocalDataSource {
  const PaymentLocalDataSource(this._database);

  final AppDatabase _database;

  Future<void> accrueMora(String cardId, {DateTime? now}) =>
      _database.transaction(
        () => MoraLocalDataSource(_database).accrue(cardId, now: now),
      );

  Stream<LateFee> watchMora(String cardId) {
    return _database
        .customSelect(
          'SELECT m.created_at, COALESCE((SELECT mora FROM enterprise_configs WHERE id = 1), 20) AS rate '
          'FROM (SELECT 1) LEFT JOIN mora m ON m.card_id = ? AND m.pagado = 0 '
          'ORDER BY m.created_at, m.id',
          variables: [Variable<String>(cardId)],
          readsFrom: {_database.mora, _database.enterpriseConfigs},
        )
        .watch()
        .map((rows) {
          final dates = rows
              .map((row) => row.readNullable<int>('created_at'))
              .whereType<int>()
              .map(
                (seconds) =>
                    DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
              )
              .toList(growable: false);
          return LateFee(
            days: dates.length,
            dueDate: dates.isEmpty ? null : dates.first,
            rate: rows.first.read<int>('rate'),
            dates: dates,
          );
        });
  }

  void _validate(PaymentInstallment installment) {
    if (!installment.amountPaid.isFinite || installment.amountPaid < 0) {
      throw ArgumentError.value(
        installment.amountPaid,
        'amountPaid',
        'El abono debe ser un importe válido y no negativo.',
      );
    }
    if ((installment.amountPaid * 100 - (installment.amountPaid * 100).round())
            .abs() >
        0.00001) {
      throw ArgumentError.value(
        installment.amountPaid,
        'amountPaid',
        'El abono admite como máximo dos decimales.',
      );
    }
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final installment in installments) {
      final scheduled = installment.scheduledDate?.toLocal();
      if (installment.isManual && scheduled != null) {
        final scheduledDay = DateTime(
          scheduled.year,
          scheduled.month,
          scheduled.day,
        );
        if (scheduledDay.isBefore(today)) {
          throw ArgumentError.value(
            installment.scheduledDate,
            'scheduledDate',
            'La fecha de una fila manual no puede ser anterior a hoy.',
          );
        }
      }
    }
    return _database.transaction(() async {
      final mora = MoraLocalDataSource(_database);
      for (final cardId in installments.map((item) => item.cardId).toSet()) {
        await mora.accrue(cardId);
      }
      for (final installment in installments) {
        final existing = await (_database.select(
          _database.payments,
        )..where((row) => row.id.equals(installment.id))).getSingleOrNull();
        if (existing == null ||
            existing.cardId != installment.cardId ||
            existing.deletedAt != null) {
          throw StateError(
            'La cuota ${installment.id} no existe en la tarjeta.',
          );
        }
        final receipt = installment.receiptNumber?.trim();
        final normalizedReceipt = receipt == null || receipt.isEmpty
            ? null
            : receipt;
        final editableFieldsChanged =
            existing.scheduledDate != installment.scheduledDate ||
            existing.amountPaid != installment.amountPaid ||
            existing.paymentType != installment.type.name ||
            existing.receiptNumber != normalizedReceipt;
        if (editableFieldsChanged &&
            existing.amountPaid > 0 &&
            existing.createdAt == null) {
          throw StateError(
            'No se puede modificar un abono sin fecha de registro.',
          );
        }
        if (editableFieldsChanged &&
            existing.createdAt != null &&
            !DateTime.now().isBefore(
              existing.createdAt!.add(const Duration(hours: 24)),
            )) {
          throw StateError(
            'No se puede modificar un abono después de 24 horas.',
          );
        }
        final firstReceipt =
            existing.createdAt == null &&
            existing.amountPaid == 0 &&
            installment.amountPaid > 0;
        final moraCents = await _applyAmount(
          existing,
          installment.amountPaid,
          mora,
        );
        final updated =
            await (_database.update(
              _database.payments,
            )..where((row) => row.id.equals(installment.id))).write(
              PaymentsCompanion(
                scheduledDate: Value(installment.scheduledDate),
                amountPaid: Value(installment.amountPaid),
                moraCents: Value(moraCents),
                paymentType: Value(installment.type.name),
                receiptNumber: Value(normalizedReceipt),
                createdAt: firstReceipt
                    ? Value(DateTime.now())
                    : const Value.absent(),
                updatedAt: editableFieldsChanged
                    ? Value(DateTime.now())
                    : const Value.absent(),
              ),
            );
        if (updated == 0) {
          throw StateError('La cuota ${installment.id} no existe.');
        }
        if (editableFieldsChanged) {
          await _database
              .into(_database.paymentChanges)
              .insert(
                PaymentChangesCompanion.insert(
                  paymentId: existing.id,
                  oldAmount: existing.amountPaid,
                  newAmount: installment.amountPaid,
                  oldMoraCents: existing.moraCents,
                  newMoraCents: moraCents,
                  oldScheduledDate: Value(existing.scheduledDate),
                  newScheduledDate: Value(installment.scheduledDate),
                  oldType: existing.paymentType,
                  newType: installment.type.name,
                  oldReceipt: Value(existing.receiptNumber),
                  newReceipt: Value(normalizedReceipt),
                  createdAt: DateTime.now(),
                ),
              );
        }
      }
      await _recalculateBalances({
        for (final installment in installments) installment.cardId,
      });
      await _reconcileCardStatuses({
        for (final installment in installments) installment.cardId,
      });
    });
  }

  Future<int> _applyAmount(
    Payment existing,
    double amount,
    MoraLocalDataSource mora,
  ) async {
    final oldCents = (existing.amountPaid * 100).round();
    final newCents = (amount * 100).round();
    var delta = newCents - oldCents;
    var applied = existing.moraCents;
    if (applied < 0 || applied > oldCents) {
      throw StateError('La asignación de mora del abono no es válida.');
    }
    if (delta == 0) return applied;
    if (delta < 0) {
      var reversal = -delta;
      final principal = oldCents - applied;
      final principalReversal = reversal < principal ? reversal : principal;
      reversal -= principalReversal;
      if (reversal > 0) {
        final applications =
            await (_database.select(_database.moraApplications)
                  ..where(
                    (row) =>
                        row.paymentId.equals(existing.id) &
                        row.reversed.equals(false),
                  )
                  ..orderBy([(row) => OrderingTerm.desc(row.id)]))
                .get();
        for (final application in applications) {
          if (reversal == 0) break;
          if (reversal < application.cents) {
            throw StateError(
              'La corrección debe revertir días completos de mora.',
            );
          }
          reversal -= application.cents;
          applied -= application.cents;
          await (_database.update(
            _database.moraApplications,
          )..where((row) => row.id.equals(application.id))).write(
            MoraApplicationsCompanion(
              reversed: const Value(true),
              reversedAt: Value(DateTime.now()),
            ),
          );
          await (_database.update(_database.mora)
                ..where((row) => row.id.equals(application.moraId)))
              .write(const MoraCompanion(pagado: Value(false)));
        }
        if (reversal != 0) {
          throw StateError(
            'No existe trazabilidad suficiente para revertir la mora.',
          );
        }
      }
      return applied;
    }

    final card = await (_database.select(
      _database.cardsTable,
    )..where((row) => row.id.equals(existing.cardId))).getSingle();
    final payments = await (_database.select(
      _database.payments,
    )..where((row) => row.cardId.equals(existing.cardId))).get();
    final paidPrincipal = payments.fold<int>(
      0,
      (sum, payment) =>
          sum + (payment.amountPaid * 100).round() - payment.moraCents,
    );
    final principalDue =
        (card.totalInstallments * card.weeklyAmount * 100).round() -
        paidPrincipal;
    if (principalDue < 0) {
      throw StateError(
        'El capital abonado excede el total de la tarjeta; corrija los registros antes de continuar.',
      );
    }
    final pending = await mora.pending(existing.cardId);
    final rate = (await mora.dailyRate()) * 100;
    if (rate < 0) throw StateError('La tarifa de mora no es válida.');
    if (pending.isNotEmpty && rate == 0) {
      throw StateError(
        'Configure una mora diaria mayor que cero antes de registrar el pago.',
      );
    }
    final totalDue = principalDue + pending.length * rate;
    if (delta > totalDue) {
      throw StateError(
        'El máximo para esta fila es Q${((oldCents + totalDue) / 100).toStringAsFixed(2)}.',
      );
    }
    if (pending.isNotEmpty && delta < rate) {
      throw StateError('El abono debe cubrir al menos un dia de mora.');
    }
    // Apply whole daily fees to the oldest days; the remainder reduces capital.
    final daysToApply = rate == 0 ? 0 : delta ~/ rate;
    for (final day in pending.take(daysToApply)) {
      delta -= rate;
      applied += rate;
      await (_database.update(_database.mora)
            ..where((row) => row.id.equals(day.id)))
          .write(const MoraCompanion(pagado: Value(true)));
      await _database
          .into(_database.moraApplications)
          .insert(
            MoraApplicationsCompanion.insert(
              paymentId: existing.id,
              moraId: day.id,
              cents: rate,
              createdAt: DateTime.now(),
            ),
          );
    }
    return applied;
  }

  Future<void> _recalculateBalances(Set<String> cardIds) async {
    for (final cardId in cardIds) {
      final card = await (_database.select(
        _database.cardsTable,
      )..where((row) => row.id.equals(cardId))).getSingle();
      final rows =
          await (_database.select(_database.payments)
                ..where(
                  (row) => row.cardId.equals(cardId) & row.deletedAt.isNull(),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.isManual),
                  (row) => OrderingTerm.asc(row.position),
                  (row) => OrderingTerm.asc(row.scheduledDate),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      var balance = card.totalInstallments * card.weeklyAmount;
      final updatedAt = DateTime.now();
      for (final row in rows) {
        balance = (balance - row.amountPaid + row.moraCents / 100).clamp(
          0,
          double.infinity,
        );
        if (row.balanceAfter != balance) {
          await (_database.update(
            _database.payments,
          )..where((payment) => payment.id.equals(row.id))).write(
            PaymentsCompanion(
              balanceAfter: Value(balance),
              updatedAt: Value(updatedAt),
            ),
          );
        }
      }
    }
  }

  Future<void> updateInstallment(PaymentInstallment installment) =>
      updateInstallments([installment]);

  Future<void> addEmptyInstallment(String cardId) {
    return _database.transaction(() async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final card = await (_database.select(
        _database.cardsTable,
      )..where((row) => row.id.equals(cardId))).getSingleOrNull();
      if (card == null) throw StateError('La tarjeta no existe.');
      final rows = await (_database.select(
        _database.payments,
      )..where((row) => row.cardId.equals(cardId))).get();
      final totalPaid = rows.fold<double>(
        0,
        (total, row) => total + row.amountPaid - row.moraCents / 100,
      );
      final position = rows.fold<int>(
        0,
        (maximum, row) =>
            row.isManual && row.position > maximum ? row.position : maximum,
      );
      await _database
          .into(_database.payments)
          .insert(
            PaymentsCompanion.insert(
              id: const Uuid().v4(),
              cardId: Value(cardId),
              balanceAfter:
                  (card.totalInstallments * card.weeklyAmount - totalPaid)
                      .clamp(0, double.infinity),
              scheduledDate: Value(today),
              isManual: const Value(true),
              position: Value(position + 1),
            ),
          );
    });
  }

  Future<void> deleteEmptyLastInstallment(String cardId, String installmentId) {
    return _database.transaction(() async {
      final rows =
          await (_database.select(_database.payments)
                ..where(
                  (row) => row.cardId.equals(cardId) & row.deletedAt.isNull(),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.isManual),
                  (row) => OrderingTerm.asc(row.position),
                  (row) => OrderingTerm.asc(row.scheduledDate),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      if (rows.isEmpty || rows.last.id != installmentId) {
        throw StateError('Solo se puede eliminar la última fila.');
      }
      final row = rows.last;
      if (!row.isManual ||
          row.amountPaid != 0 ||
          row.createdAt != null ||
          row.paymentType != PaymentType.cash.name ||
          row.receiptNumber != null) {
        throw StateError('Solo se puede eliminar una fila manual vacía.');
      }
      final now = DateTime.now();
      await (_database.update(
        _database.payments,
      )..where((payment) => payment.id.equals(installmentId))).write(
        PaymentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  Future<void> _reconcileCardStatuses(Set<String> cardIds) async {
    if (cardIds.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final card in await (_database.select(
      _database.cardsTable,
    )..where((row) => row.id.isIn(cardIds))).get()) {
      final payments =
          await (_database.select(_database.payments)..where(
                (row) => row.cardId.equals(card.id) & row.deletedAt.isNull(),
              ))
              .get();
      final paid = payments.fold<double>(
        0,
        (total, payment) =>
            total + payment.amountPaid - payment.moraCents / 100,
      );
      final pending = card.totalInstallments * card.weeklyAmount - paid;
      final hasOverdueInstallment = payments.any((payment) {
        if (payment.isManual) return false;
        final scheduled = payment.scheduledDate?.toLocal();
        if (scheduled == null) return false;
        return DateTime(
              scheduled.year,
              scheduled.month,
              scheduled.day,
            ).isBefore(today) &&
            payment.amountPaid - payment.moraCents / 100 <
                card.weeklyAmount - 0.005;
      });
      final currentStatus = CardStatus.values.firstWhere(
        (status) => status.name == card.status,
        orElse: () => CardStatus.active,
      );
      final moraSource = MoraLocalDataSource(_database);
      final days = await moraSource.pending(card.id);
      final fee = days.length * await moraSource.dailyRate();
      final status = currentStatus.forBalance(
        pendingBalance: pending + (days.isNotEmpty && fee <= 0 ? 0.01 : fee),
        hasOverdueInstallment: hasOverdueInstallment,
      );
      if (status != currentStatus) {
        final client = await (_database.select(
          _database.clientsTable,
        )..where((row) => row.id.equals(card.clientId))).getSingleOrNull();
        await (_database.update(
          _database.cardsTable,
        )..where((row) => row.id.equals(card.id))).write(
          CardsTableCompanion(
            status: Value(status.name),
            updatedAt: Value(now),
          ),
        );
        if (status == CardStatus.debtor) {
          await OperationalNotificationsLocalDataSource(_database).add(
            eventKey:
                'debtor:${card.id}:${today.toIso8601String().substring(0, 10)}',
            type: 'debtor',
            cardId: card.id,
            folderId: card.folderId,
            title: 'Tarjeta pasó a Deudor',
            message:
                '${client?.fullName ?? 'El cliente'} tiene una cuota vencida sin liquidar.',
            createdAt: now,
          );
        } else if (status == CardStatus.renewal) {
          await OperationalNotificationsLocalDataSource(_database).add(
            eventKey: 'renewal_ready:${card.id}',
            type: 'renewal_ready',
            cardId: card.id,
            folderId: card.folderId,
            title: 'Tarjeta lista para renovación',
            message:
                '${client?.fullName ?? 'El cliente'} liquidó el capital y puede iniciar el flujo de renovación.',
            createdAt: now,
          );
        }
      }
    }
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
              createdAt: row.createdAt,
              createdAtEstimated: row.createdAtEstimated,
              isManual: row.isManual,
              moraCents: row.moraCents,
            ),
          )
          .toList(growable: false);
    });
  }
}
