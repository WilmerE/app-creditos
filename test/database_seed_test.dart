import 'package:creditos/app.dart';
import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/core/database/database_seed.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/credit_card.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/domain/services/payment_plan_calculator.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/widgets/tarjeta_digital_widget.dart';
import 'package:creditos/injection_container.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 5);
  late AppDatabase db;
  late DatabaseSeed seed;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    seed = DatabaseSeed(db);
  });
  tearDown(() => db.close());

  test(
    'creates consistent clients, histories, plans, balances and statuses',
    () async {
      expect(await seed.run(now: today), DatabaseSeedResult.inserted);
      final clients = await db.select(db.clientsTable).get();
      final phones = await db.select(db.clientPhones).get();
      final cards = await db.select(db.cardsTable).get();
      final payments = await db.select(db.payments).get();
      expect(clients, hasLength(80));
      expect(phones, hasLength(80));
      expect(cards, hasLength(200));
      expect(clients.map((c) => c.id).toSet(), hasLength(80));
      expect(clients.map((c) => c.fullName).toSet(), hasLength(80));
      expect(phones.map((p) => p.phoneNumber).toSet(), hasLength(80));
      expect(
        phones.every((p) => RegExp(r'^5\d{7}$').hasMatch(p.phoneNumber)),
        isTrue,
      );
      for (final department in ['Zacapa', 'Chiquimula', 'Guatemala']) {
        expect(
          clients.where((c) => c.address.contains(department)),
          isNotEmpty,
        );
      }

      final byStatus = <String, int>{};
      var paidRows = 0;
      var partialRows = 0;
      var emptyRows = 0;
      final receipts = <String>{};
      for (final client in clients) {
        expect(client.alias, isNotEmpty);
        expect(
          phones.where((phone) => phone.clientId == client.id),
          hasLength(1),
        );
        final history =
            cards.where((card) => card.clientId == client.id).toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        expect([1, 2, 5], contains(history.length));
        expect(history.first.createdAt.isAfter(client.createdAt), isTrue);
        expect(
          history.where((card) => card.status != CardStatus.paid.name).length,
          lessThanOrEqualTo(1),
        );
        for (var index = 0; index < history.length; index++) {
          final card = history[index];
          byStatus.update(card.status, (count) => count + 1, ifAbsent: () => 1);
          if (index < history.length - 1) {
            expect(card.status, CardStatus.paid.name);
          }
          if (card.status == CardStatus.renewal.name) {
            expect(index, greaterThan(0));
          }
          expect(
            PaymentPlanCalculator.optionsFor(card.requestedAmount),
            contains(PlanOption(card.totalInstallments, card.weeklyAmount)),
          );
          final rows = payments.where((p) => p.cardId == card.id).toList()
            ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
          expect(rows, hasLength(card.totalInstallments));
          expect(
            rows.first.scheduledDate,
            DateTime(
              card.startDate.year,
              card.startDate.month,
              card.startDate.day + 5,
            ),
          );
          if (index + 1 < history.length) {
            expect(
              rows.last.scheduledDate.isBefore(history[index + 1].startDate),
              isTrue,
            );
          }
          var balance = card.weeklyAmount * card.totalInstallments;
          for (var i = 0; i < rows.length; i++) {
            final row = rows[i];
            expect(row.isRenewal, index > 0);
            if (i > 0) {
              final previous = rows[i - 1].scheduledDate;
              expect(
                row.scheduledDate,
                DateTime(previous.year, previous.month, previous.day + 7),
              );
            }
            balance -= row.amountPaid;
            expect(row.balanceAfter, closeTo(balance, 0.001));
            if (row.amountPaid == 0) {
              emptyRows++;
            } else {
              expect(row.scheduledDate.isAfter(today), isFalse);
              if (row.amountPaid < card.weeklyAmount) {
                partialRows++;
              } else {
                paidRows++;
              }
            }
            if (row.paymentType != 'cash') {
              expect(row.receiptNumber, isNotNull);
              expect(receipts.add(row.receiptNumber!), isTrue);
            } else {
              expect(row.receiptNumber, isNull);
            }
          }
          if (card.status == CardStatus.paid.name) {
            expect(balance, 0);
          } else {
            expect(balance, greaterThan(0));
            if (card.status == CardStatus.debtor.name) {
              expect(
                rows.any(
                  (row) =>
                      row.scheduledDate.isBefore(today) &&
                      row.amountPaid < card.weeklyAmount,
                ),
                isTrue,
              );
            } else {
              expect(
                rows
                    .where((row) => row.scheduledDate.isBefore(today))
                    .every((row) => row.amountPaid >= card.weeklyAmount),
                isTrue,
              );
            }
          }
        }
      }
      expect(byStatus, {
        'active': 22,
        'debtor': 22,
        'paid': 141,
        'renewal': 15,
      });
      expect(paidRows, greaterThan(0));
      expect(partialRows, greaterThan(0));
      expect(emptyRows, greaterThan(0));
      final thousandPlans = cards
          .where((card) => card.requestedAmount == 1000)
          .map((card) => card.totalInstallments)
          .toSet();
      expect(thousandPlans, {4, 7});
      expect(
        payments.every((p) => cards.any((card) => card.id == p.cardId)),
        isTrue,
      );
    },
  );

  test('is idempotent and preserves edits when run again', () async {
    await seed.run(now: today);
    final first = (await db.select(db.clientsTable).get()).first;
    await (db.update(db.clientsTable)..where((c) => c.id.equals(first.id)))
        .write(const ClientsTableCompanion(fullName: Value('Nombre editado')));
    expect(await seed.run(now: today), DatabaseSeedResult.alreadyInserted);
    expect(await db.select(db.clientsTable).get(), hasLength(80));
    expect(await db.select(db.cardsTable).get(), hasLength(200));
    expect(
      (await (db.select(
        db.clientsTable,
      )..where((c) => c.id.equals(first.id))).getSingle()).fullName,
      'Nombre editado',
    );
  });

  test('concurrent seed attempts create only one dataset', () async {
    final results = await Future.wait([
      seed.run(now: today),
      seed.run(now: today),
    ]);
    expect(
      results,
      containsAll([
        DatabaseSeedResult.inserted,
        DatabaseSeedResult.alreadyInserted,
      ]),
    );
    expect(await db.select(db.clientsTable).get(), hasLength(80));
    expect(await db.select(db.cardsTable).get(), hasLength(200));
  });

  test('refuses to seed a nonempty business database', () async {
    await db
        .into(db.clientsTable)
        .insert(
          ClientsTableCompanion.insert(
            id: 'existing',
            fullName: 'Cliente existente',
            address: 'Guatemala',
            createdAt: today,
            updatedAt: today,
          ),
        );
    await expectLater(seed.run(now: today), throwsStateError);
    expect(
      (await db.select(db.clientsTable).get()).single.fullName,
      'Cliente existente',
    );
    expect(await db.select(db.cardsTable).get(), isEmpty);
    expect(await db.select(db.syncMetadata).get(), isEmpty);
  });

  test('refuses orphan phone or payment rows without deleting them', () async {
    await db
        .into(db.clientPhones)
        .insert(
          ClientPhonesCompanion.insert(
            clientId: 'existing',
            phoneNumber: '55555555',
          ),
        );
    await expectLater(seed.run(now: today), throwsStateError);
    expect(await db.select(db.clientPhones).get(), hasLength(1));
    await db.delete(db.clientPhones).go();
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: 'existing',
            scheduledDate: today,
            balanceAfter: 100,
          ),
        );
    await expectLater(seed.run(now: today), throwsStateError);
    expect(await db.select(db.payments).get(), hasLength(1));
    expect(await db.select(db.clientsTable).get(), isEmpty);
  });

  test('rolls back all rows and marker if an insert fails', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_seed BEFORE INSERT ON cards BEGIN SELECT RAISE(ABORT, 'seed failure'); END",
    );
    await expectLater(seed.run(now: today), throwsA(isA<Exception>()));
    expect(await db.select(db.clientsTable).get(), isEmpty);
    expect(await db.select(db.clientPhones).get(), isEmpty);
    expect(await db.select(db.cardsTable).get(), isEmpty);
    expect(await db.select(db.payments).get(), isEmpty);
    expect(await db.select(db.syncMetadata).get(), isEmpty);
    await db.customStatement('DROP TRIGGER fail_seed');
    expect(await seed.run(now: today), DatabaseSeedResult.inserted);
  });

  testWidgets('requires confirmation before loading data', (tester) async {
    getIt.registerSingleton<AppDatabase>(db);
    addTearDown(() => getIt.unregister<AppDatabase>());
    await tester.pumpWidget(const CreditosApp());
    await tester.tap(find.text('Cargar datos de prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(() => db.select(db.clientsTable).get()),
      isEmpty,
    );
    await tester.tap(find.text('Cargar datos de prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cargar datos'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(
      find.text('Se cargaron 80 clientes y 200 tarjetas de prueba.'),
      findsOneWidget,
    );
    expect(
      await tester.runAsync(() async {
        return (db.select(
          db.cardsTable,
        )..orderBy([(c) => OrderingTerm.asc(c.createdAt)])).get();
      }),
      hasLength(200),
    );
  });

  testWidgets(
    'seeded complete payments produce checks, partial payment does not',
    (tester) async {
      await tester.runAsync(() => seed.run(now: today));
      final card = await tester.runAsync(
        () async => (await db.select(db.cardsTable).get()).firstWhere(
          (card) => card.status == CardStatus.active.name,
        ),
      );
      final rows = await tester.runAsync(
        () =>
            PaymentLocalDataSource(db).watchInstallmentsByCard(card!.id).first,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TarjetaDigitalWidget(
                customer: TarjetaCustomerInfo(
                  name: 'Cliente de prueba',
                  address: 'Guatemala',
                  phone: '',
                  dpi: '',
                  reference: '',
                  startDate: card!.startDate,
                  requestedAmount: card.requestedAmount,
                  paymentPlan: 'Plan',
                ),
                initialBalance: card.weeklyAmount * card.totalInstallments,
                weeklyAmount: card.weeklyAmount,
                payments: rows!,
                onAutoSave: (_) async {},
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      expect(rows[2].amountPaid, lessThan(card.weeklyAmount));
    },
  );
}
