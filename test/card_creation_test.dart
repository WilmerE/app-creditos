import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/core/database/transaction_runner.dart';
import 'package:creditos/core/utils/currency_formatter.dart';
import 'package:creditos/features/clientes/data/datasources/client_local_datasource.dart';
import 'package:creditos/features/clientes/domain/entities/client.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/credit_card_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/repositories/credit_card_repository_impl.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/credit_card.dart';
import 'package:creditos/features/cobros_tarjetas/domain/services/payment_plan_calculator.dart';
import 'package:creditos/features/cobros_tarjetas/domain/use_cases/create_card_with_new_client.dart';
import 'package:creditos/features/cobros_tarjetas/domain/use_cases/credit_card_creation.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/bloc/card_creation_cubit.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/screens/card_creation_screen.dart';
import 'package:creditos/features/clientes/domain/repositories/client_repository.dart';

// Wednesday: next Monday is 2026-11-09, first Saturday 2026-11-14.
final _wednesday = DateTime(2026, 11, 4, 10);

Client _client() => Client(
  id: 'c1',
  fullName: 'Ana López',
  address: 'Zona 1',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

class _FakeClients implements ClientRepository {
  @override
  Stream<List<Client>> watchClients({String query = ''}) =>
      Stream.value([_client()]);
  @override
  Future<Client?> getById(String id) async => null;
  @override
  Future<void> save(Client client, {String? newPhotoSourcePath}) async {}
  @override
  Future<void> delete(String id) async {}
}

void main() {
  group('PaymentPlanCalculator', () {
    PaymentPlan plan(double amount, {PlanOption? option}) =>
        PaymentPlanCalculator.calculate(
          requestedAmount: amount,
          cardId: 'x',
          option: option,
          now: _wednesday,
        );

    test('applies the fixed plans', () {
      expect(plan(500).option, const PlanOption(6, 125));
      expect(plan(1000).option, const PlanOption(4, 320));
      expect(
        plan(1000, option: const PlanOption(7, 210)).installments,
        hasLength(7),
      );
      expect(plan(1500).option, const PlanOption(6, 320));
      expect(plan(2000).option, const PlanOption(8, 320));
    });

    test('uses (amount / 1000) * 4 weeks of Q320 above Q2,000', () {
      expect(plan(5000).option, const PlanOption(20, 320));
      expect(plan(3000).option.installments, 12);
    });

    test('schedules Saturdays starting the week of next Monday', () {
      final p = plan(500);
      expect(p.startDate, DateTime(2026, 11, 9));
      expect(p.installments.first.scheduledDate, DateTime(2026, 11, 14));
      expect(p.installments[1].scheduledDate, DateTime(2026, 11, 21));
      expect(
        p.installments.every(
          (i) => i.scheduledDate.weekday == DateTime.saturday,
        ),
        isTrue,
      );
      expect(p.projectedBalance(5), 0);
    });

    test('preserves custom dates and repeats weekly across months', () {
      final result = PaymentPlanCalculator.calculate(
        requestedAmount: 500,
        cardId: 'x',
        startDate: DateTime(2024, 2, 27, 15),
        firstPaymentDate: DateTime(2024, 2, 29, 10),
      );
      expect(result.startDate, DateTime(2024, 2, 27));
      expect(result.installments.first.scheduledDate, DateTime(2024, 2, 29));
      expect(result.installments[1].scheduledDate, DateTime(2024, 3, 7));
      expect(result.installments.last.scheduledDate, DateTime(2024, 4, 4));
      expect(
        () => PaymentPlanCalculator.calculate(
          requestedAmount: 500,
          cardId: 'x',
          startDate: DateTime(2024, 3, 1),
          firstPaymentDate: DateTime(2024, 2, 29),
        ),
        throwsA(isA<InvalidPlanAmountException>()),
      );
    });

    test('rejects amounts without a plan', () {
      expect(() => plan(700), throwsA(isA<InvalidPlanAmountException>()));
      expect(PaymentPlanCalculator.isSupported(2600), isFalse);
    });
  });

  group('CreditCardCreation (Drift)', () {
    late AppDatabase db;
    late CreditCardCreation creation;
    late CreditCardRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await ClientLocalDataSource(db).insert(_client());
      repo = CreditCardRepositoryImpl(
        CreditCardLocalDataSource(db),
        PaymentLocalDataSource(db),
      );
      creation = CreditCardCreation(repo);
    });
    tearDown(() => db.close());

    Future<String> create() => creation(
      clientId: 'c1',
      requestedAmount: 500,
      colorHex: '#1565C0',
      now: _wednesday,
    );

    test('creates the first card with its schedule', () async {
      final id = await create();
      final balances = await repo.openCardBalances('c1');
      expect(balances.single.card.id, id);
      expect(balances.single.card.status, CardStatus.active);
      expect(balances.single.pending, 750);
      expect(await db.select(db.payments).get(), hasLength(6));
    });

    test('persists exact custom dates for an existing client', () async {
      final id = await creation(
        clientId: 'c1',
        requestedAmount: 500,
        colorHex: '#1565C0',
        startDate: DateTime(2024, 2, 27),
        firstPaymentDate: DateTime(2024, 2, 29),
      );
      expect((await repo.getCard(id))!.startDate, DateTime(2024, 2, 27));
      final rows = await repo.watchInstallments(id).first;
      expect(rows.first.scheduledDate, DateTime(2024, 2, 29));
      expect(rows[1].scheduledDate, DateTime(2024, 3, 7));
    });

    test('blocks renewal while the previous card has a balance', () async {
      await create();
      expect(await creation.isRenewalBlocked('c1'), isTrue);
      await expectLater(create(), throwsA(isA<RenewalBlockedException>()));
      expect(await db.select(db.cardsTable).get(), hasLength(1));
    });

    test('allows renewal after settling and marks it as renewal', () async {
      final first = await create();
      await (db.update(db.payments)..where((p) => p.cardId.equals(first)))
          .write(const PaymentsCompanion(amountPaid: Value(125)));
      expect(await creation.isRenewalBlocked('c1'), isFalse);

      final second = await create();
      final cards = await db.select(db.cardsTable).get();
      expect(cards.firstWhere((c) => c.id == first).status, 'paid');
      expect(cards.firstWhere((c) => c.id == second).status, 'renewal');
      final renewalRows = await (db.select(
        db.payments,
      )..where((p) => p.cardId.equals(second))).get();
      expect(renewalRows.every((p) => p.isRenewal), isTrue);
    });
  });

  testWidgets('screen previews the plan and enables saving', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await ClientLocalDataSource(db).insert(_client());
    final creation = CreditCardCreation(
      CreditCardRepositoryImpl(
        CreditCardLocalDataSource(db),
        PaymentLocalDataSource(db),
      ),
    );
    final clients = _FakeClients();
    final cubit = CardCreationCubit(
      clients,
      creation,
      CreateCardWithNewClient(clients, creation, DriftTransactionRunner(db)),
    );
    addTearDown(cubit.close);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await cubit.start(preselected: _client());
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CardCreationView(lockedClient: true),
        ),
      ),
    );
    expect(find.text('Fecha de Inicio del Crédito'), findsOneWidget);
    expect(find.text('Fecha del Primer Día de Pago'), findsOneWidget);
    final selectedDay = cubit.state.startDate!.day == 1 ? 2 : 1;
    await tester.tap(find.text('Fecha de Inicio del Crédito'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('$selectedDay').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(cubit.state.startDate!.day, selectedDay);
    cubit.selectFirstPaymentDate(
      DateTime(
        cubit.state.startDate!.year,
        cubit.state.startDate!.month,
        1,
      ).subtract(const Duration(days: 1)),
    );
    await tester.pump();
    await tester.pump();
    expect(cubit.state.datesValid, isFalse);
    expect(
      find.text('El primer pago no puede ser anterior al inicio del crédito.'),
      findsOneWidget,
    );
    cubit.selectFirstPaymentDate(cubit.state.startDate!);
    await tester.pump();
    await tester.tap(find.text(CurrencyFormatter.formatGtq(1000)));
    await tester.pump();
    expect(find.text('FECHA'), findsOneWidget);
    expect(
      find.text('4 x ${CurrencyFormatter.formatGtq(320)}'),
      findsOneWidget,
    );
    expect(cubit.state.canSubmit, isTrue);

    await tester.tap(find.text('7 x ${CurrencyFormatter.formatGtq(210)}'));
    await tester.pump();
    expect(cubit.state.plan!.installments, hasLength(7));
  });

  test('new client mode creates client and card transactionally', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final local = ClientLocalDataSource(db);
    final clients = _DbClients(local);
    final creation = CreditCardCreation(
      CreditCardRepositoryImpl(
        CreditCardLocalDataSource(db),
        PaymentLocalDataSource(db),
      ),
    );
    final cubit = CardCreationCubit(
      clients,
      creation,
      CreateCardWithNewClient(clients, creation, DriftTransactionRunner(db)),
    );
    addTearDown(cubit.close);

    cubit
      ..setMode(ClientMode.newClient)
      ..selectAmount(500)
      ..selectStartDate(DateTime(2024, 2, 27))
      ..selectFirstPaymentDate(DateTime(2024, 2, 29));
    expect(cubit.state.canSubmit, isFalse);
    cubit.updateDraft(const NewClientDraft(name: 'Luis', address: 'Zona 3'));
    expect(cubit.state.canSubmit, isTrue);

    await cubit.submit();
    expect(cubit.state.status, CardCreationStatus.success);
    final created = await local.findClients();
    expect(created.single.fullName, 'Luis');
    expect(
      await CreditCardLocalDataSource(db).cardsForClient(created.single.id),
      hasLength(1),
    );
    expect(await creation.blockedClientIds(), {created.single.id});
    final card = (await db.select(db.cardsTable).get()).single;
    final installments = await (db.select(
      db.payments,
    )..orderBy([(p) => OrderingTerm.asc(p.scheduledDate)])).get();
    expect(card.startDate, DateTime(2024, 2, 27));
    expect(installments.first.scheduledDate, DateTime(2024, 2, 29));
    expect(installments[1].scheduledDate, DateTime(2024, 3, 7));

    // A failing card creation rolls the client back.
    final failing = CreateCardWithNewClient(
      clients,
      creation,
      DriftTransactionRunner(db),
    );
    await expectLater(
      failing(
        client: Client(
          id: 'c2',
          fullName: 'Rollback',
          address: 'x',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
        requestedAmount: 777,
        colorHex: '#800020',
      ),
      throwsA(anything),
    );
    expect(await local.getById('c2'), isNull);
  });
}

class _DbClients extends _FakeClients {
  _DbClients(this._local);

  final ClientLocalDataSource _local;

  @override
  Future<void> save(Client client, {String? newPhotoSourcePath}) =>
      _local.insert(client);
}
