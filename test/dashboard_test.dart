import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/core/database/database_seed.dart';
import 'package:creditos/features/clientes/data/datasources/client_local_datasource.dart';
import 'package:creditos/features/clientes/data/repositories/client_repository_impl.dart';
import 'package:creditos/features/clientes/data/services/client_photo_storage.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/credit_card_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/repositories/credit_card_repository_impl.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/credit_card.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/bloc/card_detail_cubit.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/screens/card_detail_screen.dart';
import 'package:creditos/features/dashboard/data/drift_dashboard_repository.dart';
import 'package:creditos/features/dashboard/domain/dashboard_repository.dart';
import 'package:creditos/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:creditos/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:creditos/injection_container.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftDashboardRepository repository;
  final today = DateTime(2026, 11, 5, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await DatabaseSeed(db).run(now: today);
    repository = DriftDashboardRepository(db);
  });
  tearDown(() => db.close());

  test('daily metrics and filter use scheduled dates and last edits, not payment dates', () {
    DashboardCard card(
      String id,
      CardStatus status,
      List<DashboardPayment> payments,
    ) => DashboardCard(
      id: id,
      clientId: id,
      clientName: id,
      alias: null,
      photoPath: null,
      status: status,
      weeklyAmount: 125,
      totalInstallments: 4,
      payments: payments,
    );
    final yesterday = DateTime(2026, 11, 4);
    final tomorrow = DateTime(2026, 11, 6);
    final cards = [
      card('a', CardStatus.active, [
        DashboardPayment(
          scheduledDate: today,
          updatedAt: yesterday,
          amountPaid: 75,
        ),
        DashboardPayment(
          scheduledDate: tomorrow,
          updatedAt: today,
          amountPaid: 25,
        ),
      ]),
      card('b', CardStatus.paid, [
        DashboardPayment(
          scheduledDate: today,
          updatedAt: today,
          amountPaid: 125,
        ),
      ]),
      card('c', CardStatus.debtor, [
        DashboardPayment(
          scheduledDate: yesterday,
          updatedAt: yesterday,
          amountPaid: 50,
        ),
      ]),
    ];
    final state = DashboardState(
      today: today,
      cards: cards,
      filter: DashboardFilter.cash,
    );
    expect(state.projectedToday, 250);
    expect(state.estimatedPaidToday, 150);
    expect(state.visibleCards.map((card) => card.id), ['a', 'b']);
    expect(cards.first.pendingBalance, 400);
    expect(cards.first.remainingInstallments, 4);
    final nextDay = DashboardState(
      today: tomorrow,
      cards: cards,
      filter: DashboardFilter.cash,
    );
    expect(nextDay.projectedToday, 125);
    expect(nextDay.estimatedPaidToday, 0);
    expect(nextDay.visibleCards.map((card) => card.id), ['a']);
  });

  test(
    'seeded dashboard has correct filters, balance and daily amounts',
    () async {
      final cards = await repository.watchCards().first;
      final state = DashboardState(
        status: DashboardStatus.ready,
        cards: cards,
        today: today,
      );
      expect(cards, hasLength(200));
      expect(state.count(CardStatus.active), 22);
      expect(state.count(CardStatus.debtor), 22);
      expect(state.count(CardStatus.renewal), 15);
      expect(state.count(CardStatus.paid), 141);
      final expectedProjection = cards.fold<double>(
        0,
        (sum, card) =>
            sum +
            card.payments
                    .where(
                      (p) =>
                          p.scheduledDate.year == today.year &&
                          p.scheduledDate.month == today.month &&
                          p.scheduledDate.day == today.day,
                    )
                    .length *
                card.weeklyAmount,
      );
      final expectedEstimate = cards.fold<double>(
        0,
        (sum, card) =>
            sum +
            card.payments
                .where(
                  (p) =>
                      p.updatedAt.toLocal().year == today.year &&
                      p.updatedAt.toLocal().month == today.month &&
                      p.updatedAt.toLocal().day == today.day,
                )
                .fold<double>(0, (subtotal, p) => subtotal + p.amountPaid),
      );
      expect(state.projectedToday, greaterThan(0));
      expect(state.projectedToday, expectedProjection);
      expect(state.estimatedPaidToday, expectedEstimate);
      expect(state.visibleCards, hasLength(22));
      final active = state.visibleCards.first;
      expect(
        active.pendingBalance,
        active.weeklyAmount * (active.totalInstallments - 2.5),
      );
      expect(active.remainingInstallments, active.totalInstallments - 2);
      expect(
        DashboardState(
          cards: cards,
          filter: DashboardFilter.cash,
          today: today,
        ).visibleCards,
        everyElement(
          predicate<DashboardCard>(
            (card) => card.payments.any(
              (p) =>
                  p.scheduledDate.year == today.year &&
                      p.scheduledDate.month == today.month &&
                      p.scheduledDate.day == today.day ||
                  p.amountPaid > 0 &&
                      p.updatedAt.toLocal().year == today.year &&
                      p.updatedAt.toLocal().month == today.month &&
                      p.updatedAt.toLocal().day == today.day,
            ),
          ),
        ),
      );
    },
  );

  test('watches payment, client and status changes', () async {
    final cubit = DashboardCubit(repository, clock: () => today)..start();
    addTearDown(cubit.close);
    await cubit.stream.firstWhere((s) => s.status == DashboardStatus.ready);
    final card = cubit.state.visibleCards.first;
    final payment = (await PaymentLocalDataSource(
      db,
    ).watchInstallmentsByCard(card.id).first).last;
    final changed = cubit.stream.firstWhere(
      (s) => s.cards.any(
        (c) => c.id == card.id && c.pendingBalance == card.pendingBalance - 25,
      ),
    );
    await PaymentLocalDataSource(db)
        .updateInstallment(payment.copyWith(amountPaid: 25));
    expect(
      (await changed).cards
          .firstWhere((c) => c.id == card.id)
          .remainingInstallments,
      card.remainingInstallments,
    );

    final renamed = cubit.stream.firstWhere(
      (s) => s.cards.any(
        (c) =>
            c.clientId == card.clientId &&
            c.clientName == 'Cliente actualizado',
      ),
    );
    await (db.update(
      db.clientsTable,
    )..where((c) => c.id.equals(card.clientId))).write(
      const ClientsTableCompanion(fullName: Value('Cliente actualizado')),
    );
    await renamed;
    final changedStatus = cubit.stream.firstWhere(
      (s) =>
          s.cards.any((c) => c.id == card.id && c.status == CardStatus.debtor),
    );
    await cubit.changeStatus(card.id, CardStatus.debtor);
    expect((await changedStatus).count(CardStatus.debtor), 23);
  });

  test('enforces safe transitions in a transaction', () async {
    final cards = await repository.watchCards().first;
    final active = cards.firstWhere((card) => card.status == CardStatus.active);
    await expectLater(
      repository.changeStatus(active.id, CardStatus.paid),
      throwsStateError,
    );
    expect(
      (await repository.watchCards().first)
          .firstWhere((c) => c.id == active.id)
          .status,
      CardStatus.active,
    );
    final olderPaid = cards.firstWhere(
      (card) =>
          card.clientId == active.clientId && card.status == CardStatus.paid,
      orElse: () => cards.firstWhere(
        (card) =>
            card.status == CardStatus.paid &&
            cards.any(
              (other) =>
                  other.clientId == card.clientId &&
                  other.status.isOpen &&
                  other.pendingBalance > 0,
            ),
      ),
    );
    await expectLater(
      repository.changeStatus(olderPaid.id, CardStatus.active),
      throwsStateError,
    );
    await repository.changeStatus(active.id, CardStatus.debtor);
    expect(
      (await repository.watchCards().first)
          .firstWhere((c) => c.id == active.id)
          .status,
      CardStatus.debtor,
    );
    await (db.update(db.payments)..where((p) => p.cardId.equals(active.id)))
        .write(PaymentsCompanion(amountPaid: Value(active.weeklyAmount)));
    await repository.changeStatus(active.id, CardStatus.paid);
    expect(
      (await repository.watchCards().first)
          .firstWhere((c) => c.id == active.id)
          .status,
      CardStatus.paid,
    );
  });

  testWidgets(
    'status menu persists a permitted transition and rejects an unsafe one',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = DashboardCubit(repository, clock: () => today);
      addTearDown(cubit.close);
      await tester.runAsync(() async {
        cubit.start();
        await cubit.stream.firstWhere((s) => s.status == DashboardStatus.ready);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(value: cubit, child: const DashboardView()),
        ),
      );
      final card = cubit.state.visibleCards.first;
      await tester.ensureVisible(find.text(card.clientName).first);
      final tile = find
          .ancestor(
            of: find.text(card.clientName).first,
            matching: find.byType(Card),
          )
          .first;
      final menu = find.descendant(
        of: tile,
        matching: find.byTooltip('Cambiar estado'),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagada').last);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        find.textContaining('No se puede marcar como pagada'),
        findsOneWidget,
      );
      expect(cubit.state.visibleCards.any((c) => c.id == card.id), isTrue);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deudor').last);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(
        cubit.state.cards.firstWhere((c) => c.id == card.id).status,
        CardStatus.debtor,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  for (final width in [360.0, 1200.0]) {
    testWidgets(
      'filters, updates status and opens the selected card at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cubit = DashboardCubit(repository, clock: () => today);
        addTearDown(cubit.close);
        getIt.registerSingleton<AppDatabase>(db);
        getIt.registerFactory<CardDetailCubit>(
          () => CardDetailCubit(
            CreditCardRepositoryImpl(
              CreditCardLocalDataSource(db),
              PaymentLocalDataSource(db),
            ),
            ClientRepositoryImpl(
              ClientLocalDataSource(db),
              ClientPhotoStorage(),
            ),
          ),
        );
        addTearDown(() async {
          await getIt.unregister<CardDetailCubit>();
          await getIt.unregister<AppDatabase>();
        });
        await tester.runAsync(() async {
          cubit.start();
          await cubit.stream.firstWhere(
            (s) => s.status == DashboardStatus.ready,
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(
              value: cubit,
              child: const DashboardView(),
            ),
          ),
        );
        expect(find.text('Activas / Al día'), findsOneWidget);
        expect(find.textContaining('Caja estimada:'), findsOneWidget);
        await tester.ensureVisible(find.text('En mora / Deudoras'));
        await tester.tap(find.text('En mora / Deudoras'));
        await tester.pump();
        expect(cubit.state.filter, DashboardFilter.debtor);
        expect(
          cubit.state.visibleCards.every((c) => c.status == CardStatus.debtor),
          isTrue,
        );
        final selected = cubit.state.visibleCards.first;
        await tester.ensureVisible(find.text(selected.clientName).first);
        final details = find.byKey(
          ValueKey('dashboard-details-${selected.id}'),
        );
        if (tester.getCenter(details).dy > 1100) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -200));
          await tester.pumpAndSettle();
        }
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.byType(CardDetailScreen), findsOneWidget);
        expect(
          tester.widget<CardDetailScreen>(find.byType(CardDetailScreen)).cardId,
          selected.id,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
