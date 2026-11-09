import 'package:creditos/features/cobros_tarjetas/domain/entities/payment_installment.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/credit_card.dart';
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
        'NOTA: En caso de incumplimiento se aplicara un recargo de Q. 20.00 diarios sobre saldo',
      ),
      findsOneWidget,
    );
    expect(find.text('FECHA'), findsOneWidget);
    expect(find.text('ABONO'), findsOneWidget);
    expect(find.text('RESTA'), findsOneWidget);
  });

  testWidgets('shows reception time from createdAt and marks estimated dates', (
    tester,
  ) async {
    final rows = [
      PaymentInstallment(
        id: 'real',
        cardId: 'credit-1',
        scheduledDate: DateTime(2026, 1, 1),
        amountPaid: 10,
        balanceAfter: 90,
        createdAt: DateTime(2026, 11, 8, 13, 45, 30),
      ),
      PaymentInstallment(
        id: 'old',
        cardId: 'credit-1',
        scheduledDate: DateTime(2026, 1, 2),
        amountPaid: 10,
        balanceAfter: 80,
        createdAt: DateTime(2026, 1, 2),
        createdAtEstimated: true,
        isManual: true,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: rows,
              onAutoSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Recibido: 08/11/2026 13:45:30'), findsOneWidget);
    expect(find.text('Estimada: 02/01/2026 00:00:00'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Plan original'), findsOneWidget);
  });

  testWidgets('shows mora separately without changing RESTA', (tester) async {
    final partial = payment.copyWith(amountPaid: 25);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [partial],
              onAutoSave: (_) async {},
              capitalPending: 75,
              lateFee: LateFee(days: 3, dueDate: DateTime(2026, 11, 5)),
            ),
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Atraso: 3 días · Mora acumulada: Q60.00 (Q20.00 diarios desde 05/11/2026)',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Capital pendiente: Q75.00 + Mora acumulada: Q60.00 = Total a pagar hoy: Q135.00',
      ),
      findsOneWidget,
    );
    expect(find.text('Q75.00'), findsOneWidget);
  });

  testWidgets('opens the persistent mora details from the banner', (
    tester,
  ) async {
    final dates = [DateTime(2026, 11, 6), DateTime(2026, 11, 7)];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [payment],
              onAutoSave: (_) async {},
              capitalPending: 100,
              enterpriseConfig: const EnterpriseConfig(mora: 30),
              lateFee: LateFee(
                days: 2,
                dueDate: dates.first,
                rate: 30,
                dates: dates,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Q. 30.00 diarios'), findsOneWidget);
    await tester.tap(find.textContaining('Atraso: 2 días'));
    await tester.pumpAndSettle();
    expect(find.text('Días de mora pendientes'), findsOneWidget);
    expect(find.text('06/11/2026'), findsOneWidget);
    expect(find.text('07/11/2026'), findsOneWidget);
  });

  testWidgets('accepts one mora day with a remainder and rejects amounts above the debt', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [payment],
              onAutoSave: (_) async {
                saves++;
              },
              capitalPending: 100,
              lateFee: LateFee(days: 2, dueDate: DateTime(2026, 11, 6)),
              debounceDuration: const Duration(milliseconds: 100),
            ),
          ),
        ),
      ),
    );
    final amount = find.byKey(const ValueKey('payment-1-amount'));
    await tester.enterText(amount, '10');
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('Abono minimo'), findsOneWidget);
    expect(saves, 0);
    await tester.enterText(amount, '30');
    await tester.pump(const Duration(milliseconds: 150));
    expect(saves, 1);
    await tester.enterText(amount, '141');
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Máximo Q140.00'), findsOneWidget);
    expect(saves, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('locks payment fields after 24 hours', (tester) async {
    final expired = PaymentInstallment(
      id: payment.id,
      cardId: payment.cardId,
      scheduledDate: payment.scheduledDate,
      amountPaid: 10,
      balanceAfter: 90,
      createdAt: DateTime.now().subtract(const Duration(hours: 25)),
      type: PaymentType.deposit,
      receiptNumber: 'R-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [expired],
              onAutoSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    for (final suffix in ['date', 'amount']) {
      final field = find
          .descendant(
            of: find.byKey(ValueKey('payment-1-$suffix')),
            matching: find.byType(EditableText),
          )
          .first;
      expect(tester.widget<EditableText>(field).readOnly, isTrue);
    }
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('payment-1-receipt')),
              matching: find.byType(EditableText),
            ),
          )
          .readOnly,
      isTrue,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<PaymentType>>(
            find.byType(DropdownButtonFormField<PaymentType>),
          )
          .onChanged,
      isNull,
    );
    expect(
      find.byTooltip('Edición bloqueada después de 24 horas'),
      findsOneWidget,
    );
  });

  testWidgets('does not show an overdue banner with zero days', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [payment],
              onAutoSave: (_) async {},
              capitalPending: 100,
              lateFee: const LateFee(),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Atraso:'), findsNothing);
    expect(find.textContaining('Mora acumulada: Q0.00'), findsOneWidget);
  });

  testWidgets('pending edits prevent deleting an apparently empty row', (
    tester,
  ) async {
    final manual = PaymentInstallment(
      id: 'manual',
      cardId: 'credit-1',
      scheduledDate: null,
      amountPaid: 0,
      balanceAfter: 100,
      isManual: true,
    );
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDigitalWidget(
              customer: customer,
              initialBalance: 100,
              payments: [manual],
              onAutoSave: (_) async {},
              onDeleteRow: (_) async {
                deleted = true;
              },
              debounceDuration: const Duration(seconds: 5),
            ),
          ),
        ),
      ),
    );
    final delete = find.ancestor(
      of: find.byTooltip('Eliminar última fila vacía'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(delete).onPressed, isNotNull);
    await tester.enterText(find.byKey(const ValueKey('manual-amount')), '20');
    await tester.pump();
    expect(tester.widget<IconButton>(delete).onPressed, isNull);
    expect(deleted, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
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
