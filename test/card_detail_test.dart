import 'package:drift/native.dart';
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
}
