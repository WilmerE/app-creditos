import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/features/clientes/data/datasources/client_local_datasource.dart';
import 'package:creditos/features/clientes/data/repositories/client_repository_impl.dart';
import 'package:creditos/features/clientes/data/services/client_photo_storage.dart';
import 'package:creditos/features/clientes/domain/entities/client.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/credit_card_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/repositories/credit_card_repository_impl.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/payment_installment.dart';
import 'package:creditos/features/cobros_tarjetas/domain/use_cases/credit_card_creation.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/bloc/card_detail_cubit.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/screens/card_detail_screen.dart';

void main() {
  late AppDatabase db;
  late CreditCardRepositoryImpl cards;
  late PaymentLocalDataSource payments;
  late String cardId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    payments = PaymentLocalDataSource(db);
    cards = CreditCardRepositoryImpl(CreditCardLocalDataSource(db), payments);
    await ClientLocalDataSource(db).insert(
      Client(
        id: 'c1',
        fullName: 'Ana López',
        address: 'Zona 1',
        phones: const ['5555-1111'],
        alias: 'YOLI DE DON NERY',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
    cardId = await CreditCardCreation(cards)(
      clientId: 'c1',
      requestedAmount: 500,
      colorHex: '#1565C0',
    );
  });
  tearDown(() => db.close());

  test('updateInstallments persists edits and validates receipts', () async {
    final first = (await payments.watchInstallmentsByCard(cardId).first).first;

    await payments.updateInstallment(
      first.copyWith(
        amountPaid: 125,
        balanceAfter: 625,
        type: PaymentType.deposit,
        receiptNumber: ' B-1 ',
      ),
    );
    final saved = (await payments.watchInstallmentsByCard(cardId).first).first;
    expect(saved.amountPaid, 125);
    expect(saved.type, PaymentType.deposit);
    expect(saved.receiptNumber, 'B-1');
    expect(saved.createdAt, isNotNull);
    expect(saved.createdAtEstimated, isFalse);
    await payments.updateInstallment(saved.copyWith(amountPaid: 100));
    final corrected =
        (await payments.watchInstallmentsByCard(cardId).first).first;
    expect(corrected.createdAt, saved.createdAt);

    expect(
      () => payments.updateInstallment(
        first.copyWith(type: PaymentType.transfer),
      ),
      throwsArgumentError,
    );
    expect(
      () => payments.updateInstallment(
        PaymentInstallment(
          id: 'missing',
          cardId: cardId,
          scheduledDate: DateTime(2026),
          amountPaid: 0,
          balanceAfter: 0,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'expired payments reject edits atomically but allow derived balances',
    () async {
      final rows = await payments.watchInstallmentsByCard(cardId).first;
      await payments.updateInstallment(rows.first.copyWith(amountPaid: 125));
      final old = DateTime.now().subtract(const Duration(hours: 25));
      await (db.update(
        db.payments,
      )..where((p) => p.id.equals(rows.first.id))).write(
        PaymentsCompanion(createdAt: Value(old), updatedAt: Value(old)),
      );
      final saved =
          (await payments.watchInstallmentsByCard(cardId).first).first;

      await expectLater(
        payments.updateInstallments([
          rows[1].copyWith(amountPaid: 10),
          saved.copyWith(amountPaid: 100),
        ]),
        throwsStateError,
      );
      final unchanged = await payments.watchInstallmentsByCard(cardId).first;
      expect(unchanged.first.amountPaid, 125);
      expect(unchanged[1].amountPaid, 0);

      await payments.updateInstallment(saved.copyWith(balanceAfter: 500));
      final row = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(saved.id))).getSingle();
      expect(row.balanceAfter, 625);
      expect(
        row.updatedAt.millisecondsSinceEpoch ~/ 1000,
        old.millisecondsSinceEpoch ~/ 1000,
      );
    },
  );

  test(
    'recalculates later locked balances without changing their timestamps',
    () async {
      final rows = await payments.watchInstallmentsByCard(cardId).first;
      await payments.updateInstallment(rows[1].copyWith(amountPaid: 50));
      final old = DateTime.now().subtract(const Duration(hours: 25));
      await (db.update(
        db.payments,
      )..where((p) => p.id.equals(rows[1].id))).write(
        PaymentsCompanion(createdAt: Value(old), updatedAt: Value(old)),
      );
      await payments.updateInstallment(
        rows.first.copyWith(amountPaid: 100, balanceAfter: -999),
      );
      final result = await payments.watchInstallmentsByCard(cardId).first;
      expect(result.first.balanceAfter, 650);
      expect(result[1].balanceAfter, 600);
      final locked = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(rows[1].id))).getSingle();
      expect(
        locked.updatedAt.millisecondsSinceEpoch ~/ 1000,
        old.millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        locked.createdAt!.millisecondsSinceEpoch ~/ 1000,
        old.millisecondsSinceEpoch ~/ 1000,
      );
    },
  );

  test('rejects invalid payment amounts at the data boundary', () async {
    final first = (await payments.watchInstallmentsByCard(cardId).first).first;
    for (final amount in [-1.0, double.nan, double.infinity]) {
      expect(
        () => payments.updateInstallment(first.copyWith(amountPaid: amount)),
        throwsArgumentError,
      );
    }
    expect(
      (await payments.watchInstallmentsByCard(cardId).first).first.amountPaid,
      0,
    );
  });

  test(
    'manual rows are ordered and only the empty last row can be deleted',
    () async {
      final original = await cards.watchInstallments(cardId).first;
      await cards.addEmptyInstallment(cardId);
      await cards.addEmptyInstallment(cardId);
      var rows = await cards.watchInstallments(cardId).first;
      expect(rows, hasLength(original.length + 2));
      expect(rows.last.isManual, isTrue);
      final now = DateTime.now();
      expect(
        rows.last.scheduledDate,
        DateTime(now.year, now.month, now.day),
      );
      expect(rows.last.balanceAfter, 750);
      await expectLater(
        cards.deleteEmptyLastInstallment(cardId, rows[rows.length - 2].id),
        throwsStateError,
      );
      await expectLater(
        cards.deleteEmptyLastInstallment(cardId, original.last.id),
        throwsStateError,
      );
      await cards.deleteEmptyLastInstallment(cardId, rows.last.id);
      rows = await cards.watchInstallments(cardId).first;
      final manual = rows.last;
      await payments.updateInstallment(manual.copyWith(amountPaid: 25));
      await expectLater(
        cards.deleteEmptyLastInstallment(cardId, manual.id),
        throwsStateError,
      );
      final paid = (await cards.watchInstallments(cardId).first).last;
      await payments.updateInstallment(paid.copyWith(amountPaid: 0));
      await expectLater(
        cards.deleteEmptyLastInstallment(cardId, manual.id),
        throwsStateError,
      );
      expect((await cards.getCard(cardId))!.totalInstallments, 6);
    },
  );

  test('manual rows reject dates before today', () async {
    await cards.addEmptyInstallment(cardId);
    final row = (await cards.watchInstallments(cardId).first).last;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await expectLater(
      payments.updateInstallment(
        row.copyWith(
          scheduledDate: DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
          ),
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'saving a payment recalculates the fee and capital reactively',
    () async {
      final first = (await cards.watchInstallments(cardId).first).first;
      await payments.updateInstallment(
        first.copyWith(scheduledDate: DateTime(2020, 1, 1)),
      );
      final today = DateTime.now();
      await db.batch((batch) {
        batch.insertAll(db.mora, [
          MoraCompanion.insert(
            cardId: cardId,
            createdAt: DateTime(today.year, today.month, today.day - 2),
          ),
          MoraCompanion.insert(
            cardId: cardId,
            createdAt: DateTime(today.year, today.month, today.day - 1),
          ),
        ]);
      });
      final cubit = CardDetailCubit(
        cards,
        ClientRepositoryImpl(ClientLocalDataSource(db), ClientPhotoStorage()),
      );
      addTearDown(cubit.close);
      await cubit.load(cardId);
      if (cubit.state.installments.isEmpty || cubit.state.lateFee.days != 2) {
        await cubit.stream.firstWhere(
          (state) => state.installments.isNotEmpty && state.lateFee.days == 2,
        );
      }
      expect(cubit.state.lateFee.amount, 40);
      final updated = cubit.stream.firstWhere(
        (state) => state.totalPaid == 85 && state.lateFee.days == 0,
      );
      await cubit.autoSave([
        cubit.state.installments.first.copyWith(amountPaid: 125),
      ]);
      final state = await updated;
      expect(state.pendingBalance, 665);
      expect(state.lateFee.amount, 0);
      expect(state.totalDueToday, 665);
    },
  );

  testWidgets('detail screen shows real data and auto-saves an edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cubit = CardDetailCubit(
      cards,
      ClientRepositoryImpl(ClientLocalDataSource(db), ClientPhotoStorage()),
    );
    addTearDown(cubit.close);
    await tester.runAsync(() => cubit.load(cardId));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: cubit, child: const CardDetailView()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.text('Ana López'), findsWidgets);
    expect(find.textContaining('YOLI DE DON NERY'), findsOneWidget);
    expect(cubit.state.installments, hasLength(6));

    final amountField = find.byKey(
      ValueKey('${cubit.state.installments.first.id}-amount'),
    );
    await tester.enterText(amountField, '125');
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    final stored = await tester.runAsync(
      () => payments.watchInstallmentsByCard(cardId).first,
    );
    expect(stored!.first.amountPaid, 125);
    expect(stored.first.balanceAfter, 625);
    expect(cubit.state.pendingBalance, 625);
  });

  testWidgets('detail adds and removes an empty manual row', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = CardDetailCubit(
      cards,
      ClientRepositoryImpl(ClientLocalDataSource(db), ClientPhotoStorage()),
    );
    addTearDown(cubit.close);
    await tester.runAsync(() => cubit.load(cardId));
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: cubit, child: const CardDetailView()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Agregar fila'));
    await tester.tap(find.text('Agregar fila'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(cubit.state.installments, hasLength(7));
    expect(find.text('Manual'), findsOneWidget);
    final row = cubit.state.installments.last;
    final now = DateTime.now();
    expect(row.scheduledDate, DateTime(now.year, now.month, now.day));
    await tester.ensureVisible(find.byTooltip('Eliminar última fila vacía'));
    await tester.tap(find.byTooltip('Eliminar última fila vacía'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(cubit.state.installments, hasLength(6));
    final persisted = await tester.runAsync(
      () => cards.watchInstallments(cardId).first,
    );
    expect(persisted, hasLength(6));
  });

  testWidgets('mora refreshes at midnight without editing payments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final first = await tester.runAsync(
      () async => (await cards.watchInstallments(cardId).first).first,
    );
    await tester.runAsync(
      () => payments.updateInstallment(
        first!.copyWith(scheduledDate: DateTime(2020, 1, 1)),
      ),
    );
    final actual = DateTime.now();
    final today = DateTime(actual.year, actual.month, actual.day);
    await tester.runAsync(
      () => db
          .into(db.moraTracking)
          .insertOnConflictUpdate(
            MoraTrackingCompanion.insert(
              cardId: cardId,
              lastCheckedAt: DateTime(today.year, today.month, today.day - 1),
            ),
          ),
    );
    var now = DateTime(today.year, today.month, today.day, 23, 59, 59, 500);
    final cubit = CardDetailCubit.withClock(
      cards,
      ClientRepositoryImpl(ClientLocalDataSource(db), ClientPhotoStorage()),
      () => now,
    );
    addTearDown(cubit.close);
    await tester.runAsync(() => cubit.load(cardId));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: cubit, child: const CardDetailView()),
      ),
    );
    expect(cubit.state.lateFee.days, 1);
    expect(cubit.state.lateFee.amount, 20);
    expect(find.textContaining('Atraso: 1 días'), findsOneWidget);
    expect(find.text('Total hoy Q770.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    now = DateTime(today.year, today.month, today.day + 1);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 650)),
    );
    await tester.pump();
    expect(cubit.state.lateFee.days, 2);
    expect(cubit.state.totalDueToday, 790);
    expect(find.textContaining('Atraso: 2 días'), findsOneWidget);
    expect(find.text('Total hoy Q790.00'), findsOneWidget);
  });
}
