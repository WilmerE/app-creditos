import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../../core/database/app_database.dart';
import '../../../domain/entities/credit_card.dart';
import '../../../domain/entities/payment_installment.dart';
import '../../../domain/use_cases/credit_card_creation.dart';
import 'mora_local_data_source.dart';

@lazySingleton
class CreditCardLocalDataSource {
  CreditCardLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<CardBalance>> openCardBalances(String clientId) =>
      _database.transaction(() async {
        final cards = await (_database.select(
          _database.cardsTable,
        )..where((c) => c.clientId.equals(clientId))).get();
        final balances = <CardBalance>[];
        for (final row in cards) {
          final card = _toEntity(row);
          final mora = MoraLocalDataSource(_database);
          if (card.status.isOpen) await mora.accrue(card.id);
          final pendingMora = await mora.pending(card.id);
          if (!card.status.isOpen && pendingMora.isEmpty) continue;
          final paid = await _totalPaid(card.id);
          final fee = pendingMora.length * await mora.dailyRate();
          balances.add(
            CardBalance(
              card,
              (card.totalToPay - paid).clamp(0, double.infinity) +
                  (pendingMora.isNotEmpty && fee <= 0 ? 0.01 : fee.toDouble()),
            ),
          );
        }
        return balances;
      });

  Future<Set<String>> clientIdsWithPendingBalance() async {
    final cards = await _database.select(_database.cardsTable).get();
    final ids = <String>{};
    for (final row in cards) {
      final card = _toEntity(row);
      if (card.status == CardStatus.debtor ||
          card.status == CardStatus.deactivated) {
        ids.add(card.clientId);
      }
      if (ids.contains(card.clientId)) continue;
      final balances = await openCardBalances(card.clientId);
      if (balances.any((balance) => balance.pending > 0.005)) {
        ids.add(card.clientId);
      }
    }
    return ids;
  }

  Future<CreditCard?> getCard(String cardId) async {
    final row = await (_database.select(
      _database.cardsTable,
    )..where((c) => c.id.equals(cardId))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  Future<List<CreditCard>> cardsForClient(String clientId) async {
    final rows =
        await (_database.select(_database.cardsTable)
              ..where((c) => c.clientId.equals(clientId))
              ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
            .get();
    return rows.map(_toEntity).toList(growable: false);
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
      final previousCards = await (_database.select(
        cards,
      )..where((row) => row.clientId.equals(card.clientId))).get();
      if (previousCards.any(
        (previous) =>
            previous.status == CardStatus.debtor.name ||
            previous.status == CardStatus.deactivated.name,
      )) {
        throw const RenewalBlockedException(
          'No se puede crear una tarjeta nueva mientras el cliente tenga una tarjeta deudora o desactivada.',
        );
      }
      final balances = await openCardBalances(card.clientId);
      if (balances.any((balance) => balance.pending > 0.005)) {
        throw const RenewalBlockedException();
      }
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
              folderId: Value(card.folderId),
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
            scheduledDate: Value(item.scheduledDate),
            amountPaid: Value(item.amountPaid),
            balanceAfter: item.balanceAfter,
            isRenewal: Value(item.isRenewal),
          ),
      ]);
    });
  }

  Future<double> _totalPaid(String cardId) async {
    final rows = await (_database.select(
      _database.payments,
    )..where((row) => row.cardId.equals(cardId))).get();
    return rows.fold<double>(
      0,
      (sum, row) => sum + row.amountPaid - row.moraCents / 100,
    );
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
    folderId: row.folderId,
  );
}
