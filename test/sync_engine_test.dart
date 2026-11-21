import 'dart:io';

import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/core/network/sync_engine.dart';
import 'package:creditos/core/network/sync_remote.dart';
import 'package:creditos/features/clientes/data/services/client_photo_storage.dart';
import 'package:creditos/features/cobros_tarjetas/data/credit_plan_repository.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/credit_card_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import 'package:creditos/features/cobros_tarjetas/data/repositories/credit_card_repository_impl.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/credit_plan.dart';
import 'package:creditos/features/dashboard/data/operational_notifications_local_data_source.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _user = 'user-1';

/// Drift stores timestamps in whole seconds; competing edits on the two
/// devices must be at least a second apart for last-write-wins to order them.
Future<void> _nextSecond() => Future<void>.delayed(const Duration(seconds: 1));

/// In-memory stand-in for Supabase with PostgREST upsert semantics: provided
/// columns are merged into the row matched on the conflict columns. It also
/// enforces the cloud foreign keys so push ordering mistakes fail here.
class _FakeCloud implements SyncRemote {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  final photos = <String, Uint8List>{};

  Map<String, Map<String, dynamic>> table(String name) =>
      tables.putIfAbsent(name, () => {});

  static const Map<String, List<(String, String, String)>> _foreignKeys = {
    'cards': [('client_id', 'clients', 'id')],
    'payments': [('card_id', 'cards', 'id')],
    'mora': [('card_id', 'cards', 'id')],
    'mora_tracking': [('card_id', 'cards', 'id')],
    'mora_applications': [
      ('payment_id', 'payments', 'id'),
      ('mora_sync_id', 'mora', 'sync_id'),
    ],
    'payment_changes': [('payment_id', 'payments', 'id')],
  };

  @override
  Future<List<Map<String, dynamic>>> selectAll(String name) async => [
    for (final row in table(name).values) Map<String, dynamic>.of(row),
  ];

  @override
  Future<void> upsert(
    String name,
    List<Map<String, Object?>> rows,
    String onConflict,
  ) async {
    final columns = onConflict.split(',');
    for (final row in rows) {
      for (final (column, target, targetColumn)
          in _foreignKeys[name] ?? const <(String, String, String)>[]) {
        final value = row[column];
        final exists = table(target).values
            .any((other) => other[targetColumn] == value);
        if (!exists) {
          throw StateError('FK $name.$column -> $target missing: $value');
        }
      }
      final key = columns.map((column) => row[column]).join('|');
      table(name).update(
        key,
        (existing) => {...existing, ...row},
        ifAbsent: () => Map<String, dynamic>.of(row),
      );
    }
  }

  @override
  Future<void> uploadPhoto(String objectPath, Uint8List bytes) async {
    photos[objectPath] = bytes;
  }

  @override
  Future<Uint8List> downloadPhoto(String objectPath) async =>
      photos[objectPath] ?? (throw StateError('missing $objectPath'));
}

class _Device {
  _Device(this.cloud, Directory photoRoot)
    : db = AppDatabase.forTesting(NativeDatabase.memory()),
      photos = ClientPhotoStorage.withRoot(photoRoot);

  final _FakeCloud cloud;
  final AppDatabase db;
  final ClientPhotoStorage photos;

  PaymentLocalDataSource get payments => PaymentLocalDataSource(db);
  CreditCardRepositoryImpl get cards =>
      CreditCardRepositoryImpl(CreditCardLocalDataSource(db), payments);

  Future<void> sync() => SyncEngine(db, cloud, _user, photos: photos).run();

  Future<void> pay(String paymentId, double amount) async {
    final row = (await payments.watchInstallmentsByCard('card').first)
        .firstWhere((installment) => installment.id == paymentId);
    await payments.updateInstallment(row.copyWith(amountPaid: amount));
  }
}

void main() {
  late _FakeCloud cloud;
  late Directory temp;
  late _Device tablet;
  late _Device phone;
  late DateTime today;
  var shownAlerts = 0;

  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset);

  /// Tablet-side card with two overdue mora days, as in mora_payment_test.
  Future<void> seedTablet({int dueOffset = 0}) async {
    final db = tablet.db;
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
            scheduledDate: Value(day(dueOffset)),
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
        MoraCompanion.insert(cardId: 'card', createdAt: day(-2)),
        MoraCompanion.insert(cardId: 'card', createdAt: day(-1)),
      ]),
    );
  }

  setUp(() async {
    final now = DateTime.now();
    today = DateTime(now.year, now.month, now.day);
    cloud = _FakeCloud();
    temp = await Directory.systemTemp.createTemp('sync_engine_test');
    tablet = _Device(cloud, Directory(p.join(temp.path, 'tablet')));
    phone = _Device(cloud, Directory(p.join(temp.path, 'phone')));
    shownAlerts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            if (call.method == 'show') shownAlerts++;
            return call.method == 'initialize' ? true : null;
          },
        );
  });

  tearDown(() async {
    await tablet.db.close();
    await phone.db.close();
    await temp.delete(recursive: true);
  });

  test('a restored phone receives mora, applications, audit and tracking, '
      'and its reversal flows back to the tablet', () async {
    await seedTablet();
    await tablet.pay('row', 30);
    await tablet.sync();

    await phone.sync();
    final paid = await phone.db.select(phone.db.payments).getSingle();
    expect(paid.amountPaid, 30);
    expect(paid.moraCents, 2000);
    expect(paid.balanceAfter, 90);
    final days = await phone.db.select(phone.db.mora).get();
    expect(days.map((row) => row.pagado), [true, false]);
    expect((await phone.cards.watchMora('card').first).amount, 20);
    final applications = await phone.db.select(phone.db.moraApplications).get();
    final tabletApplications = await tablet.db
        .select(tablet.db.moraApplications)
        .get();
    expect(applications.single.syncId, tabletApplications.single.syncId);
    expect(applications.single.syncId, isNotEmpty);
    expect(
      (await phone.db.select(phone.db.paymentChanges).get()).single.newAmount,
      30,
    );
    expect(
      (await phone.db.select(phone.db.moraTracking).getSingle()).lastCheckedAt,
      today,
    );

    // The backup phone reverts the receipt within the 24-hour window.
    await _nextSecond();
    await phone.pay('row', 0);
    await phone.sync();
    await tablet.sync();

    final tabletDays = await tablet.db.select(tablet.db.mora).get();
    expect(tabletDays.map((row) => row.pagado), [false, false]);
    final reverted = await tablet.db
        .select(tablet.db.moraApplications)
        .getSingle();
    expect(reverted.reversed, isTrue);
    final payment = await tablet.db.select(tablet.db.payments).getSingle();
    expect(payment.amountPaid, 0);
    expect(payment.moraCents, 0);
    expect(payment.balanceAfter, 100);
    expect(
      await tablet.db.select(tablet.db.paymentChanges).get(),
      hasLength(2),
    );
    expect((await tablet.cards.watchMora('card').first).amount, 40);
    expect(cloud.table('mora').values.map((row) => row['pagado']), [
      false,
      false,
    ]);
  });

  test('both devices accruing the same day keep a single mora row', () async {
    await seedTablet();
    await tablet.sync();
    await phone.sync();
    for (final device in [tablet, phone]) {
      await device.db
          .into(device.db.mora)
          .insert(MoraCompanion.insert(cardId: 'card', createdAt: today));
    }
    await tablet.sync();
    await phone.sync();
    await tablet.sync();
    expect(cloud.table('mora'), hasLength(3));
    expect(await tablet.db.select(tablet.db.mora).get(), hasLength(3));
    expect(await phone.db.select(phone.db.mora).get(), hasLength(3));
  });

  test(
    'a device that counted from a later checkpoint re-accrues the gap',
    () async {
      await seedTablet(dueOffset: -6);
      await tablet.db.delete(tablet.db.mora).go();
      await tablet.db
          .update(tablet.db.moraTracking)
          .write(MoraTrackingCompanion(lastCheckedAt: Value(day(-3))));
      await tablet.db.batch(
        (batch) => batch.insertAll(tablet.db.mora, [
          for (final offset in [-5, -4, -3])
            MoraCompanion.insert(cardId: 'card', createdAt: day(offset)),
        ]),
      );
      await tablet.sync();
      await phone.sync();
      // The phone believes it already checked today, as a fresh install would.
      await phone.db
          .update(phone.db.moraTracking)
          .write(MoraTrackingCompanion(lastCheckedAt: Value(today)));
      // ...while the cloud still holds the tablet's older checkpoint.
      cloud.table('mora_tracking')['card']!['last_checked_at'] = day(-3)
          .toUtc()
          .toIso8601String();

      await phone.sync();
      final days = await phone.db.select(phone.db.mora).get();
      expect(days.map((row) => row.createdAt), [
        for (var offset = -5; offset <= 0; offset++) day(offset),
      ]);
      expect(cloud.table('mora'), hasLength(6));
      expect(
        DateTime.parse(
          cloud.table('mora_tracking')['card']!['last_checked_at'] as String,
        ).toLocal(),
        today,
      );
    },
  );

  test('derived balances are recomputed on the receiving device', () async {
    await seedTablet();
    await tablet.db
        .into(tablet.db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: 'second',
            cardId: const Value('card'),
            scheduledDate: Value(day(7)),
            balanceAfter: 100,
          ),
        );
    await tablet.db.delete(tablet.db.mora).go();
    await tablet.pay('second', 50);
    await tablet.sync();
    await phone.sync();
    expect(
      (await phone.db.select(phone.db.payments).get()).map(
        (row) => row.balanceAfter,
      ),
      [100, 50],
    );

    // The second row is now locked; correcting the first one changes its
    // balance without bumping its timestamp, so it is not re-uploaded.
    final old = DateTime.now().subtract(const Duration(hours: 25));
    for (final device in [tablet, phone]) {
      await (device.db.update(
        device.db.payments,
      )..where((row) => row.id.equals('second'))).write(
        PaymentsCompanion(createdAt: Value(old), updatedAt: Value(old)),
      );
    }
    cloud.table('payments')['second']!['updated_at'] = old
        .toUtc()
        .toIso8601String();
    await _nextSecond();
    await tablet.pay('row', 20);
    await tablet.sync();
    await phone.sync();
    final rows = await phone.db.select(phone.db.payments).get();
    expect(rows.map((row) => row.balanceAfter), [80, 30]);
  });

  test('notifications merge read state without raising alerts again', () async {
    await seedTablet();
    final notices = OperationalNotificationsLocalDataSource(tablet.db);
    await notices.add(
      eventKey: 'debtor:card:2026-11-21',
      type: 'debtor',
      cardId: 'card',
      title: 'Tarjeta pasó a Deudor',
      message: 'Cliente',
    );
    expect(shownAlerts, 1);
    await tablet.sync();
    await phone.sync();
    expect(shownAlerts, 1);
    final received = await phone.db
        .select(phone.db.operationalNotifications)
        .getSingle();
    expect(received.cardId, 'card');
    expect(received.isRead, isFalse);

    // The phone generating the same event later does not duplicate it.
    await OperationalNotificationsLocalDataSource(phone.db).add(
      eventKey: 'debtor:card:2026-11-21',
      type: 'debtor',
      cardId: 'card',
      title: 'Tarjeta pasó a Deudor',
      message: 'Cliente',
    );
    expect(shownAlerts, 1);

    await OperationalNotificationsLocalDataSource(phone.db).markAllRead();
    await phone.sync();
    await tablet.sync();
    expect(
      (await tablet.db.select(tablet.db.operationalNotifications).getSingle())
          .isRead,
      isTrue,
    );
  });

  test('credit plans sync additions and deletions without duplicating the '
      'factory catalog', () async {
    final tabletPlans = CreditPlanRepository(tablet.db);
    final phonePlans = CreditPlanRepository(phone.db);
    final factory = await tabletPlans.getAll();
    await tabletPlans.save(
      const CreditPlan(
        id: null,
        amount: 800,
        installments: 10,
        installmentAmount: 100,
        isActive: true,
      ),
    );
    await tabletPlans.delete(factory.first.id!);
    await tablet.sync();
    await phone.sync();

    final received = await phonePlans.getAll();
    expect(received, hasLength(factory.length));
    expect(
      received.map((plan) => (plan.amount, plan.installments)),
      containsAll([(800.0, 10)]),
    );
    expect(
      received.any(
        (plan) =>
            plan.amount == factory.first.amount &&
            plan.installments == factory.first.installments,
      ),
      isFalse,
    );
    expect(cloud.table('credit_plans'), hasLength(factory.length + 1));

    // Re-creating the deleted plan on the phone revives it everywhere.
    await _nextSecond();
    await phonePlans.save(
      CreditPlan(
        id: null,
        amount: factory.first.amount,
        installments: factory.first.installments,
        installmentAmount: factory.first.installmentAmount,
        isActive: true,
      ),
    );
    await phone.sync();
    await tablet.sync();
    expect(await tabletPlans.getAll(), hasLength(factory.length + 1));
  });

  test('client photos are uploaded and restored on the other device', () async {
    await seedTablet();
    final source = File(p.join(temp.path, 'source.jpg'));
    await source.writeAsBytes([1, 2, 3, 4]);
    final stored = await tablet.photos.store(source.path, 'client');
    await (tablet.db.update(
      tablet.db.clientsTable,
    )..where((row) => row.id.equals('client'))).write(
      ClientsTableCompanion(
        photoPath: Value(stored),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await tablet.sync();
    expect(cloud.photos.keys.single, startsWith('$_user/client_'));

    await phone.sync();
    final client = await phone.db.select(phone.db.clientsTable).getSingle();
    expect(client.photoPath, isNotNull);
    expect(client.photoPath, startsWith(p.join(temp.path, 'phone')));
    expect(await File(client.photoPath!).readAsBytes(), [1, 2, 3, 4]);

    // Removing the photo on the tablet removes it from the phone too.
    await _nextSecond();
    await (tablet.db.update(
      tablet.db.clientsTable,
    )..where((row) => row.id.equals('client'))).write(
      ClientsTableCompanion(
        photoPath: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await tablet.sync();
    await phone.sync();
    final cleared = await phone.db.select(phone.db.clientsTable).getSingle();
    expect(cleared.photoPath, isNull);
    expect(await File(client.photoPath!).exists(), isFalse);
  });

  test(
    'a cloud row from an older app version never deletes a local photo',
    () async {
      await seedTablet();
      final source = File(p.join(temp.path, 'source.jpg'));
      await source.writeAsBytes([9, 9]);
      final stored = await tablet.photos.store(source.path, 'client');
      await (tablet.db.update(tablet.db.clientsTable)
            ..where((row) => row.id.equals('client')))
          .write(ClientsTableCompanion(photoPath: Value(stored)));
      // A newer edit from a device that does not know about photo_object.
      await tablet.sync();
      final row = cloud.table('clients')['client']!;
      row.remove('photo_object');
      row['full_name'] = 'Editado en otro equipo';
      row['updated_at'] = DateTime.now()
          .add(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String();

      await tablet.sync();
      final client = await tablet.db.select(tablet.db.clientsTable).getSingle();
      expect(client.fullName, 'Editado en otro equipo');
      expect(client.photoPath, stored);
      expect(await File(stored).exists(), isTrue);
    },
  );

  test(
    'the same plan created on both devices before syncing is merged',
    () async {
      const plan = CreditPlan(
        id: null,
        amount: 900,
        installments: 9,
        installmentAmount: 110,
        isActive: true,
      );
      await CreditPlanRepository(tablet.db).save(plan);
      await CreditPlanRepository(phone.db).save(plan);
      await tablet.sync();
      await phone.sync();
      await tablet.sync();
      final tabletPlans = await CreditPlanRepository(tablet.db).getAll();
      final phonePlans = await CreditPlanRepository(phone.db).getAll();
      expect(tabletPlans.where((plan) => plan.amount == 900), hasLength(1));
      expect(phonePlans.where((plan) => plan.amount == 900), hasLength(1));
      expect(
        cloud
            .table('credit_plans')
            .values
            .where((row) => row['amount_cents'] == 90000),
        hasLength(1),
      );
      expect(phonePlans, hasLength(tabletPlans.length));
    },
  );
}
