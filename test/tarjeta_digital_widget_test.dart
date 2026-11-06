import 'package:creditos/features/cobros_tarjetas/domain/entities/payment_installment.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/widgets/tarjeta_digital_widget.dart';
import 'package:creditos/features/enterprise/domain/enterprise_config.dart';
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

  testWidgets('renders the physical-card header and one payment table', (
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
    expect(find.text('FECHA'), findsOneWidget);
    expect(find.text('ABONO'), findsOneWidget);
    expect(find.text('RESTA'), findsOneWidget);
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
    expect(find.text('FECHA'), findsOneWidget);
  });

  testWidgets('checks paid installments but not partial or future rows', (
    tester,
  ) async {
    final payments = [
      for (final (index, amount) in [25.0, 50.0, 25.0, 0.0].indexed)
        PaymentInstallment(
          id: 'payment-$index',
          cardId: 'credit-1',
          scheduledDate: DateTime(2026, 11, 5 + index * 7),
          amountPaid: amount,
          balanceAfter: 100,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              weeklyAmount: 50,
              payments: payments,
              onAutoSave: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.bySemanticsLabel('Cuota saldada'), findsNWidgets(2));
  });

  testWidgets('shows only enabled enterprise fields with values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [payment],
              enterpriseConfig: const EnterpriseConfig(
                name: 'Empresa Ejemplo',
                phone: '12345678',
                nit: '123-K',
                email: 'empresa@example.com',
                bankAccount: '987',
                showPhone: true,
                showEmail: true,
              ),
              onAutoSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Empresa Ejemplo'), findsOneWidget);
    expect(
      find.textContaining('Teléfono empresa: 12345678', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('empresa@example.com', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('123-K', findRichText: true), findsNothing);
    expect(find.textContaining('987', findRichText: true), findsNothing);
  });

  for (final width in [320.0, 900.0]) {
    testWidgets('highlights a visible bank account at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TarjetaDigitalWidget(
                customer: customer,
                initialBalance: 100,
                payments: [payment],
                enterpriseConfig: const EnterpriseConfig(
                  phone: '55551111',
                  nit: '123-K',
                  bankAccount: '1234-5678-9012-3456',
                  showPhone: true,
                  showNit: true,
                  showBankAccount: true,
                ),
                onAutoSave: (_) async {},
              ),
            ),
          ),
        ),
      );

      final account = find.text('Cuenta bancaria: 1234-5678-9012-3456');
      expect(account, findsOneWidget);
      final text = tester.widget<Text>(account);
      expect(text.style!.fontWeight, FontWeight.bold);
      final containers = find.ancestor(
        of: account,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).borderRadius != null &&
              (widget.decoration! as BoxDecoration).color != null,
        ),
      );
      final decoration =
          tester.widget<Container>(containers.first).decoration!
              as BoxDecoration;
      expect(decoration.color!.a, closeTo(0.1, 0.001));
      expect(
        find.textContaining('Teléfono empresa: 55551111', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('NIT: 123-K', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('does not show an empty enabled bank account', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [payment],
              enterpriseConfig: const EnterpriseConfig(
                bankAccount: '  ',
                showBankAccount: true,
              ),
              onAutoSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Cuenta bancaria'), findsNothing);
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

  testWidgets('does not mark a payment as settled when saving fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              weeklyAmount: 50,
              payments: [payment],
              debounceDuration: const Duration(milliseconds: 100),
              onAutoSave: (_) async =>
                  throw StateError('error de almacenamiento'),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-1-amount')),
      '50',
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.textContaining('No se pudo guardar el pago'), findsOneWidget);
  });
}
