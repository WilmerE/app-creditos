import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/credit_card_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/repositories/credit_card_repository_impl.dart';
import 'package:creditos/features/cobros_tarjetas/domain/use_cases/credit_card_creation.dart';
import 'package:creditos/features/dashboard/data/drift_dashboard_repository.dart';
import 'package:creditos/features/enterprise/data/enterprise_config_repository.dart';
import 'package:creditos/features/enterprise/domain/enterprise_config.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PaymentLocalDataSource payments;
  late CreditCardRepositoryImpl cards;
  late DateTime today;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    payments = PaymentLocalDataSource(db);
    cards = CreditCardRepositoryImpl(CreditCardLocalDataSource(db), payments);
    final now = DateTime.now();
    today = DateTime(now.year, now.month, now.day);
    await db
        .into(db.clientsTable)
        .insert(
          ClientsTableCompanion.insert(
            id: 'client',
            fullName: 'Cliente',
            address: 'Zona',
            createdAt: today,
            updatedAt: today,
          ),
        );
    await db
        .into(db.cardsTable)
        .insert(
          CardsTableCompanion.insert(
            id: 'card',
            clientId: 'client',
            requestedAmount: 100,
            deliveredAmount: 100,
            totalInstallments: 2,
            weeklyAmount: 50,
            startDate: today,
            createdAt: today,
          ),
        );
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: 'row',
            cardId: const Value('card'),
            scheduledDate: Value(today),
            balanceAfter: 100,
          ),
        );
    await db
        .into(db.moraTracking)
        .insert(
          MoraTrackingCompanion.insert(cardId: 'card', lastCheckedAt: today),
        );
    await db.batch(
      (batch) => batch.insertAll(db.mora, [
        MoraCompanion.insert(
          cardId: 'card',
          createdAt: DateTime(today.year, today.month, today.day - 2),
        ),
        MoraCompanion.insert(
          cardId: 'card',
          createdAt: DateTime(today.year, today.month, today.day - 1),
        ),
      ]),
    );
  });
  tearDown(() => db.close());

  Future<void> save(double amount) async {
    final row = (await cards.watchInstallments('card').first).single;
    await payments.updateInstallment(row.copyWith(amountPaid: amount));
  }

  test('accepts at least one complete mora day and applies any remainder to capital', () async {
    await expectLater(save(19.99), throwsStateError);
    await expectLater(save(10), throwsStateError);
    await expectLater(save(140.01), throwsStateError);
    expect(
      (await db.select(db.mora).get()).every((row) => !row.pagado),
      isTrue,
    );
    expect((await db.select(db.payments).getSingle()).amountPaid, 0);

    await save(30);
    var days = await db.select(db.mora).get();
    expect(days.map((day) => day.pagado), [true, false]);
    var row = await db.select(db.payments).getSingle();
    expect(row.moraCents, 2000);
    expect(row.balanceAfter, 90);
    await save(65);
    days = await db.select(db.mora).get();
    expect(days.every((day) => day.pagado), isTrue);
    row = await db.select(db.payments).getSingle();
    expect(row.moraCents, 4000);
    expect(row.balanceAfter, 75);
    expect((await db.select(db.moraApplications).get()), hasLength(2));
  });

  test('a Q40 payment covers two Q20 mora days and leaves capital unchanged', () async {
    await save(40);
    final days = await db.select(db.mora).get();
    expect(days.map((day) => day.pagado), [true, true]);
    final row = await db.select(db.payments).getSingle();
    expect(row.moraCents, 4000);
    expect(row.balanceAfter, 100);
  });
  test('reversal removes principal first then whole days at their original paid amounts', () async {
    await save(65);
    await save(45);
    var row = await db.select(db.payments).getSingle();
    expect(row.moraCents, 4000);
    expect(row.balanceAfter, 95);
    await expectLater(save(10), throwsStateError);
    expect((await db.select(db.payments).getSingle()).amountPaid, 45);
    await save(20);
    row = await db.select(db.payments).getSingle();
    expect(row.moraCents, 2000);
    expect(row.balanceAfter, 100);
    expect(
      (await db.select(db.moraApplications).get()).where((a) => a.reversed),
      hasLength(1),
    );
    expect((await db.select(db.mora).get()).map((day) => day.pagado), [
      true,
      false,
    ]);
  });

  test('renewal and dashboard account for outstanding mora even with zero principal', () async {
    await save(140);
    await db
        .into(db.mora)
        .insert(
          MoraCompanion.insert(
            cardId: 'card',
            createdAt: DateTime(today.year, today.month, today.day - 3),
          ),
        );
    final creation = CreditCardCreation(cards);
    expect(await creation.isRenewalBlocked('client'), isTrue);
    final dashboard = (await DriftDashboardRepository(
      db,
    ).watchCards().first).single;
    expect(dashboard.pendingBalance, 20);
    expect(dashboard.status.name, isNot('renewal'));
    await expectLater(
      creation(clientId: 'client', requestedAmount: 500, colorHex: '#000000'),
      throwsA(isA<RenewalBlockedException>()),
    );
  });

  test(
    'accrual catches up once per elapsed local day and ignores manual dates',
    () async {
      await (db.delete(db.mora)).go();
      await (db.update(
        db.moraTracking,
      )..where((t) => t.cardId.equals('card'))).write(
        MoraTrackingCompanion(
          lastCheckedAt: Value(
            DateTime(today.year, today.month, today.day - 3),
          ),
        ),
      );
      await (db.update(db.payments)..where((p) => p.id.equals('row'))).write(
        PaymentsCompanion(
          scheduledDate: Value(
            DateTime(today.year, today.month, today.day - 5),
          ),
        ),
      );
      await cards.accrueMora('card');
      await cards.accrueMora('card');
      final days = await db.select(db.mora).get();
      expect(days, hasLength(3));
      expect(days.map((row) => row.createdAt.day).toSet(), hasLength(3));
      expect((await cards.watchMora('card').first).amount, 60);
    },
  );

  test(
    'changing the rate affects unpaid days and reversals retain the paid rate',
    () async {
      await save(30);
      await EnterpriseConfigRepository(db)
          .save(const EnterpriseConfig(mora: 30));
      expect((await cards.watchMora('card').first).amount, 30);
      await expectLater(save(49), throwsStateError);
      await save(50);
      await save(30);
      final days = await db.select(db.mora).get();
      expect(days.map((day) => day.pagado), [true, false]);
      expect((await cards.watchMora('card').first).amount, 30);
      final changes = await db.select(db.paymentChanges).get();
      expect(changes.map((change) => change.newAmount), [20, 50, 20]);
      expect(changes.last.oldMoraCents, 5000);
      expect(changes.last.newMoraCents, 2000);
    },
  );

  test('unpaid mora on a paid card also blocks renewal', () async {
    await (db.update(db.cardsTable)..where((row) => row.id.equals('card')))
        .write(const CardsTableCompanion(status: Value('paid')));
    final creation = CreditCardCreation(cards);
    expect(await creation.isRenewalBlocked('client'), isTrue);
    expect(await creation.blockedClientIds(), contains('client'));
  });

  test('settling capital and all mora moves the card to renewal', () async {
    await save(140);
    final payment = await db.select(db.payments).getSingle();
    expect(payment.balanceAfter, 0);
    expect(payment.moraCents, 4000);
    expect((await db.select(db.cardsTable).getSingle()).status, 'renewal');
    expect(await CreditCardCreation(cards).isRenewalBlocked('client'), isFalse);
    expect((await cards.watchMora('card').first).amount, 0);
  });

  test('zero mora rate cannot write off outstanding days', () async {
    await db
        .into(db.enterpriseConfigs)
        .insert(
          EnterpriseConfigsCompanion.insert(
            id: const Value(1),
            name: 'Empresa',
            phone: '',
            nit: '',
            email: '',
            bankAccount: '',
            showPhone: false,
            showNit: false,
            showEmail: false,
            showBankAccount: false,
            mora: const Value(0),
          ),
        );
    await expectLater(save(20), throwsStateError);
    expect(
      (await db.select(db.mora).get()).every((day) => !day.pagado),
      isTrue,
    );
    expect(await CreditCardCreation(cards).isRenewalBlocked('client'), isTrue);
    expect(
      () =>
          EnterpriseConfigRepository(db).save(const EnterpriseConfig(mora: 0)),
      throwsArgumentError,
    );
  });

  test('foreign keys reject mora for a nonexistent card', () async {
    await expectLater(
      db
          .into(db.mora)
          .insert(MoraCompanion.insert(cardId: 'missing', createdAt: today)),
      throwsA(isA<Exception>()),
    );
  });
}
