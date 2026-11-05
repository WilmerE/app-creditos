import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../../core/database/app_database.dart';
import '../../../domain/entities/credit_card.dart';
import '../../../domain/entities/payment_installment.dart';

@lazySingleton
class CreditCardLocalDataSource {
  CreditCardLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<CardBalance>> openCardBalances(String clientId) async {
    final cards = await (_database.select(
      _database.cardsTable,
    )..where((c) => c.clientId.equals(clientId))).get();
    final balances = <CardBalance>[];
    for (final row in cards) {
      final card = _toEntity(row);
      if (!card.status.isOpen) continue;
      final paid = await _totalPaid(card.id);
      balances.add(CardBalance(card, card.totalToPay - paid));
    }
    return balances;
  }

  Future<bool> hasPreviousCards(String clientId) async {
    final count = _database.cardsTable.id.count();
    final query = _database.selectOnly(_database.cardsTable)
      ..addColumns([count])
      ..where(_database.cardsTable.clientId.equals(clientId));
    return (await query.map((row) => row.read(count)).getSingle() ?? 0) > 0;
  }

  Future<void> createCard(CreditCard card, List<PaymentInstallment> schedule) {
    return _database.transaction(() async {
      final cards = _database.cardsTable;
      final balances = await openCardBalances(card.clientId);
      for (final balance in balances.where((b) => b.pending <= 0.005)) {
        await (_database.update(cards)
              ..where((c) => c.id.equals(balance.card.id)))
            .write(CardsTableCompanion(status: Value(CardStatus.paid.name)));
      }

      await _database
          .into(cards)
          .insert(
            CardsTableCompanion.insert(
              id: card.id,
              clientId: card.clientId,
              requestedAmount: card.requestedAmount,
              deliveredAmount: card.deliveredAmount,
              totalInstallments: card.totalInstallments,
              weeklyAmount: card.weeklyAmount,
              status: Value(card.status.name),
              colorHex: Value(card.colorHex),
              startDate: card.startDate,
              createdAt: card.createdAt,
            ),
          );
      await _database.savePayments([
        for (final item in schedule)
          PaymentsCompanion.insert(
            id: item.id,
            cardId: Value(item.cardId),
            scheduledDate: item.scheduledDate,
            amountPaid: Value(item.amountPaid),
            balanceAfter: item.balanceAfter,
            isRenewal: Value(item.isRenewal),
          ),
      ]);
    });
  }

  Future<double> _totalPaid(String cardId) async {
    final sum = _database.payments.amountPaid.sum();
    final query = _database.selectOnly(_database.payments)
      ..addColumns([sum])
      ..where(_database.payments.cardId.equals(cardId));
    return await query.map((row) => row.read(sum)).getSingle() ?? 0;
  }

  CreditCard _toEntity(CardRow row) => CreditCard(
    id: row.id,
    clientId: row.clientId,
    requestedAmount: row.requestedAmount,
    deliveredAmount: row.deliveredAmount,
    totalInstallments: row.totalInstallments,
    weeklyAmount: row.weeklyAmount,
    status: CardStatus.values.firstWhere(
      (s) => s.name == row.status,
      orElse: () => CardStatus.active,
    ),
    colorHex: row.colorHex,
    startDate: row.startDate,
    createdAt: row.createdAt,
  );
}
