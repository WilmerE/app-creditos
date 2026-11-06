import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../cobros_tarjetas/domain/entities/credit_card.dart';
import '../domain/dashboard_repository.dart';

class DriftDashboardRepository implements DashboardRepository {
  const DriftDashboardRepository(this._db);

  final AppDatabase _db;
  static const _epsilon = 0.005;

  @override
  Stream<List<DashboardCard>> watchCards() {
    final cards = _db.cardsTable;
    final clients = _db.clientsTable;
    final payments = _db.payments;
    final query =
        _db.select(cards).join([
            innerJoin(clients, clients.id.equalsExp(cards.clientId)),
            leftOuterJoin(payments, payments.cardId.equalsExp(cards.id)),
          ])
          ..where(clients.deletedAt.isNull())
          ..orderBy([
            OrderingTerm.asc(clients.fullName),
            OrderingTerm.desc(cards.createdAt),
            OrderingTerm.asc(payments.scheduledDate),
          ]);
    return query.watch().map((rows) {
      final grouped = <String, (CardRow, ClientRow, List<DashboardPayment>)>{};
      for (final row in rows) {
        final card = row.readTable(cards);
        final client = row.readTable(clients);
        final group = grouped.putIfAbsent(card.id, () => (card, client, []));
        final payment = row.readTableOrNull(payments);
        if (payment != null) {
          group.$3.add(
            DashboardPayment(
              scheduledDate: payment.scheduledDate,
              updatedAt: payment.updatedAt,
              amountPaid: payment.amountPaid,
            ),
          );
        }
      }
      return grouped.values
          .map((group) {
            final (card, client, installments) = group;
            if (card.weeklyAmount <= 0 || card.totalInstallments <= 0) {
              throw StateError('La tarjeta ${card.id} tiene un plan inválido.');
            }
            return DashboardCard(
              id: card.id,
              clientId: client.id,
              clientName: client.fullName,
              alias: client.alias,
              photoPath: client.photoPath,
              status: CardStatus.values.byName(card.status),
              weeklyAmount: card.weeklyAmount,
              totalInstallments: card.totalInstallments,
              payments: List.unmodifiable(installments),
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
      if (card.status == status.name) return;

      final related = await (_db.select(
        cards,
      )..where((c) => c.clientId.equals(card.clientId))).get();
      final totals = <String, double>{};
      final rows = await (_db.select(
        _db.payments,
      )..where((p) => p.cardId.isIn(related.map((c) => c.id)))).get();
      for (final row in rows) {
        totals.update(
          row.cardId,
          (value) => value + row.amountPaid,
          ifAbsent: () => row.amountPaid,
        );
      }
      double pending(CardRow row) =>
          row.totalInstallments * row.weeklyAmount - (totals[row.id] ?? 0);

      if (status == CardStatus.paid && pending(card) > _epsilon) {
        throw StateError(
          'No se puede marcar como pagada una tarjeta con saldo pendiente.',
        );
      }
      if (status.isOpen &&
          related.any(
            (other) =>
                other.id != card.id &&
                CardStatus.values.byName(other.status).isOpen &&
                pending(other) > _epsilon,
          )) {
        throw StateError(
          'El cliente ya tiene otra tarjeta abierta con saldo pendiente.',
        );
      }
      await (_db.update(cards)..where((c) => c.id.equals(cardId))).write(
        CardsTableCompanion(status: Value(status.name)),
      );
    });
  }
}
