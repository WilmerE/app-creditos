import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/core/utils/currency_formatter.dart';
import 'package:creditos/features/clientes/data/datasources/client_local_datasource.dart';
import 'package:creditos/features/clientes/domain/entities/client.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/credit_card.dart';

void main() {
  test('formats amounts with a decimal point', () {
    expect(CurrencyFormatter.formatGtq(320), 'Q320.00');
    expect(CurrencyFormatter.formatGtq(1000), 'Q1,000.00');
    expect(CurrencyFormatter.formatGtq(62.5), 'Q62.50');
  });

  test('activeCardsCount counts only open cards per client', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = ClientLocalDataSource(db);
    final now = DateTime(2026, 11, 4);
    await clients.insert(
      Client(
        id: 'c1',
        fullName: 'Ana',
        address: 'Z1',
        phones: const ['11111111', '22222222'],
        createdAt: now,
        updatedAt: now,
      ),
    );
    Future<void> add(String id, CardStatus status) => db
        .into(db.cardsTable)
        .insert(
          CardsTableCompanion.insert(
            id: id,
            clientId: 'c1',
            requestedAmount: 500,
            deliveredAmount: 500,
            totalInstallments: 6,
            weeklyAmount: 125,
            status: Value(status.name),
            startDate: now,
            createdAt: now,
          ),
        )
        .then((_) {});
    await add('a', CardStatus.paid);
    await add('b', CardStatus.active);
    await add('c', CardStatus.renewal);

    final found = await clients.findClients();
    expect(found.single.activeCardsCount, 2);
    expect(found.single.phones, ['11111111', '22222222']);
    expect((await clients.getById('c1'))!.activeCardsCount, 2);
  });
}
