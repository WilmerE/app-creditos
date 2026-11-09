import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../cobros_tarjetas/domain/entities/credit_card.dart';
import '../../cobros_tarjetas/data/datasources/local/mora_local_data_source.dart';
import '../domain/dashboard_repository.dart';

class DriftDashboardRepository implements DashboardRepository {
  const DriftDashboardRepository(this._db);

  final AppDatabase _db;
  static const _epsilon = 0.005;

  @override
  Stream<List<DashboardCard>> watchCards() async* {
    await _db.transaction(() async {
      final all = await _db.select(_db.cardsTable).get();
      for (final card in all) {
        if (CardStatus.values.byName(card.status).isOpen) {
          await MoraLocalDataSource(_db).accrue(card.id);
        }
      }
    });
    final cards = _db.cardsTable;
    final clients = _db.clientsTable;
    final payments = _db.payments;
    final mora = _db.mora;
    final configs = _db.enterpriseConfigs;
    final phones = _db.clientPhones;
    final query =
        _db.select(cards).join([
            innerJoin(clients, clients.id.equalsExp(cards.clientId)),
            leftOuterJoin(payments, payments.cardId.equalsExp(cards.id)),
            leftOuterJoin(
              mora,
              mora.cardId.equalsExp(cards.id) & mora.pagado.equals(false),
            ),
            leftOuterJoin(configs, configs.id.equals(1)),
            leftOuterJoin(phones, phones.clientId.equalsExp(clients.id)),
          ])
          ..where(clients.deletedAt.isNull())
          ..orderBy([
            OrderingTerm.asc(clients.fullName),
            OrderingTerm.desc(cards.createdAt),
            OrderingTerm.asc(payments.scheduledDate),
            OrderingTerm.asc(phones.position),
          ]);
    yield* query.watch().map((rows) {
      final grouped =
          <
            String,
            (
              CardRow,
              ClientRow,
              Map<String, DashboardPayment>,
              Set<int>,
              int,
              List<String>,
            )
          >{};
      for (final row in rows) {
        final card = row.readTable(cards);
        final client = row.readTable(clients);
        final group = grouped.putIfAbsent(
          card.id,
          () => (
            card,
            client,
            {},
            {},
            row.readTableOrNull(configs)?.mora ?? 20,
            <String>[],
          ),
        );
        final payment = row.readTableOrNull(payments);
        final late = row.readTableOrNull(mora);
        final phone = row.readTableOrNull(phones);
        if (phone != null && !group.$6.contains(phone.phoneNumber)) {
          group.$6.add(phone.phoneNumber);
        }
        if (late != null) group.$4.add(late.id);
        if (payment != null) {
          group.$3[payment.id] = DashboardPayment(
            scheduledDate: payment.scheduledDate,
            updatedAt: payment.updatedAt,
            amountPaid: payment.amountPaid,
            isManual: payment.isManual,
            moraPaid: payment.moraCents / 100,
          );
        }
      }
      return grouped.values
          .map((group) {
            final (card, client, paymentMap, overdueDays, rate, clientPhones) =
                group;
            final installments = paymentMap.values.toList(growable: false);
            final moraAmount = overdueDays.length * rate;
            if (card.weeklyAmount <= 0 || card.totalInstallments <= 0) {
              throw StateError('La tarjeta ${card.id} tiene un plan inválido.');
            }
            final pendingBalance =
                (card.totalInstallments * card.weeklyAmount -
                        installments.fold<double>(
                          0,
                          (total, payment) =>
                              total + payment.amountPaid - payment.moraPaid,
                        ))
                    .clamp(0, double.infinity) +
                (overdueDays.isNotEmpty && moraAmount <= 0
                    ? 0.01
                    : moraAmount.toDouble());
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final hasOverdueInstallment = installments.any((payment) {
              if (payment.isManual) return false;
              final scheduled = payment.scheduledDate?.toLocal();
              if (scheduled == null) return false;
              return DateTime(
                    scheduled.year,
                    scheduled.month,
                    scheduled.day,
                  ).isBefore(today) &&
                  payment.amountPaid - payment.moraPaid <
                      card.weeklyAmount - _epsilon;
            });
            final storedStatus = CardStatus.values.byName(card.status);
            return DashboardCard(
              id: card.id,
              clientId: client.id,
              clientName: client.fullName,
              alias: client.alias,
              photoPath: client.photoPath,
              primaryPhone: clientPhones.isEmpty ? null : clientPhones.first,
              status: storedStatus.forBalance(
                pendingBalance: pendingBalance,
                hasOverdueInstallment: hasOverdueInstallment,
              ),
              weeklyAmount: card.weeklyAmount,
              totalInstallments: card.totalInstallments,
              payments: List.unmodifiable(installments),
              outstandingMora: moraAmount.toDouble(),
            );
          })
          .toList(growable: false);
    });
  }

  @override
  Future<void> changeStatus(String cardId, CardStatus status) {
    if (status == CardStatus.archived) {
      throw ArgumentError('El estado archivado no está disponible aquí.');
    }
    return _db.transaction(() async {
      final cards = _db.cardsTable;
      final card = await (_db.select(
        cards,
      )..where((c) => c.id.equals(cardId))).getSingleOrNull();
      if (card == null) throw StateError('La tarjeta ya no existe.');

      final related = await (_db.select(
        cards,
      )..where((c) => c.clientId.equals(card.clientId))).get();
      final moraSource = MoraLocalDataSource(_db);
      for (final other in related) {
        if (CardStatus.values.byName(other.status).isOpen) {
          await moraSource.accrue(other.id);
        }
      }
      final rate = await moraSource.dailyRate();
      final fees = <String, double>{};
      for (final other in related) {
        final days = await moraSource.pending(other.id);
        fees[other.id] = days.isNotEmpty && rate <= 0
            ? 0.01
            : (days.length * rate).toDouble();
      }
      final totals = <String, double>{};
      final rows = await (_db.select(
        _db.payments,
      )..where((p) => p.cardId.isIn(related.map((c) => c.id)))).get();
      for (final row in rows) {
        totals.update(
          row.cardId,
          (value) => value + row.amountPaid - row.moraCents / 100,
          ifAbsent: () => row.amountPaid - row.moraCents / 100,
        );
      }
      double pending(CardRow row) =>
          (row.totalInstallments * row.weeklyAmount - (totals[row.id] ?? 0))
              .clamp(0, double.infinity) +
          (fees[row.id] ?? 0);

      final cardPending = pending(card);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final hasOverdueInstallment = rows.any((payment) {
        if (payment.cardId != cardId || payment.isManual) return false;
        final scheduled = payment.scheduledDate?.toLocal();
        if (scheduled == null) return false;
        return DateTime(
              scheduled.year,
              scheduled.month,
              scheduled.day,
            ).isBefore(today) &&
            payment.amountPaid - payment.moraCents / 100 <
                card.weeklyAmount - _epsilon;
      });
      final currentStatus = CardStatus.values
          .byName(card.status)
          .forBalance(
            pendingBalance: cardPending,
            hasOverdueInstallment: hasOverdueInstallment,
          );
      final allowedTransition = switch (currentStatus) {
        CardStatus.debtor => status == CardStatus.deactivated,
        CardStatus.deactivated => status == CardStatus.active,
        CardStatus.renewal => status == CardStatus.paid,
        _ => status != CardStatus.deactivated,
      };
      if (!allowedTransition) {
        throw StateError(switch (currentStatus) {
          CardStatus.debtor => 'Una tarjeta deudora solo puede desactivarse.',
          CardStatus.deactivated =>
            'Una tarjeta desactivada solo puede reactivarse.',
          CardStatus.renewal =>
            'Una tarjeta en renovación solo puede pasar a pagada.',
          _ => 'Transición de estado no permitida.',
        });
      }
      if (status == CardStatus.renewal && cardPending > _epsilon) {
        throw StateError(
          'No se puede marcar como en renovación una tarjeta con saldo pendiente.',
        );
      }
      if (status == CardStatus.paid && pending(card) > _epsilon) {
        throw StateError(
          'No se puede marcar como pagada una tarjeta con saldo pendiente.',
        );
      }
      if (status.isOpen &&
          status != CardStatus.deactivated &&
          related.any(
            (other) =>
                other.id != card.id &&
                (CardStatus.values.byName(other.status).isOpen ||
                    (fees[other.id] ?? 0) > _epsilon) &&
                pending(other) > _epsilon,
          )) {
        throw StateError(
          'El cliente ya tiene otra tarjeta abierta con saldo pendiente.',
        );
      }
      if ((status == CardStatus.active || status == CardStatus.debtor) &&
          cardPending <= _epsilon &&
          currentStatus != CardStatus.deactivated) {
        throw StateError(
          'Una tarjeta sin saldo pendiente debe estar en renovación o pagada.',
        );
      }
      if (card.status == status.name) return;
      await (_db.update(cards)..where((c) => c.id.equals(cardId))).write(
        CardsTableCompanion(status: Value(status.name)),
      );
    });
  }
}
