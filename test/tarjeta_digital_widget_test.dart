import 'package:creditos/features/cobros_tarjetas/domain/entities/payment_installment.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/widgets/tarjeta_digital_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final payment = PaymentInstallment(
    id: 'payment-1',
    cardId: 'credit-1',
    scheduledDate: DateTime(2026, 11, 5),
    amountPaid: 0,
    balanceAfter: 100,
  );
  final customer = TarjetaCustomerInfo(
    name: 'Yoli',
    address: 'Guatemala',
    phone: '5555-5555',
    dpi: '1234567890101',
    reference: 'YOLI DE DON NERY',
    startDate: DateTime(2026, 11, 1),
    requestedAmount: 100,
    paymentPlan: '10 cuotas',
  );

  testWidgets('renders the physical-card header and two payment grids', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TarjetaDigitalWidget(
            customer: customer,
            initialBalance: 100,
            payments: [payment],
            onAutoSave: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('V&\$ INVERSIONES'), findsOneWidget);
    expect(find.textContaining('YOLI DE DON NERY'), findsOneWidget);
    expect(
      find.text(
        'NOTA: En caso de incumplimiento se aplicara un recargo de Q. 20 diarios sobre saldo',
      ),
      findsOneWidget,
    );
    expect(find.text('FECHA'), findsNWidgets(2));
    expect(find.text('ABONO'), findsNWidgets(2));
    expect(find.text('RESTA'), findsNWidgets(2));
  });

  Widget buildCard() => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TarjetaDigitalWidget(
          customer: customer,
          initialBalance: 100,
          payments: [payment],
          onAutoSave: (_) async {},
        ),
      ),
    ),
  );

  testWidgets('uses a single table on narrow touch screens', (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildCard());

    expect(find.text('FECHA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('centers the card with a max width on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildCard());

    final size = tester.getSize(find.byType(Card));
    expect(size.width, 960);
    expect(tester.getCenter(find.byType(Card)).dx, 900);
    expect(find.text('FECHA'), findsNWidgets(2));
  });

  testWidgets('auto-saves an edited amount and recalculates the balance', (
    tester,
  ) async {
    final savedBatches = <List<PaymentInstallment>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TarjetaDigitalWidget(
            customer: customer,
            initialBalance: 100,
            payments: [payment],
            debounceDuration: const Duration(milliseconds: 300),
            onAutoSave: (batch) async => savedBatches.add(batch),
          ),
        ),
      ),
    );

    final amountField = find.byType(TextFormField).at(1);
    await tester.ensureVisible(amountField);
    await tester.enterText(amountField, '25');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(savedBatches, hasLength(1));
    expect(savedBatches.single.single.amountPaid, 25);
    expect(savedBatches.single.single.balanceAfter, 75);
  });
}
