import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class SyncMetadata extends Table {
  TextColumn get key => text()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('ClientRow')
class ClientsTable extends Table {
  @override
  String get tableName => 'clients';

  TextColumn get id => text()();
  TextColumn get fullName => text()();
  TextColumn get address => text()();
  TextColumn get dpi => text().nullable()();
  TextColumn get dpiFolder => text().nullable()();
  TextColumn get alias => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ClientPhones extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text()();
  TextColumn get phoneNumber => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

@DataClassName('CardRow')
class CardsTable extends Table {
  @override
  String get tableName => 'cards';

  TextColumn get id => text()();
  TextColumn get clientId => text().references(ClientsTable, #id)();
  RealColumn get requestedAmount => real()();
  RealColumn get deliveredAmount => real()();
  IntColumn get totalInstallments => integer()();
  RealColumn get weeklyAmount => real()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get colorHex => text().withDefault(const Constant('#800020'))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('EnterpriseConfigRow')
class EnterpriseConfigs extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  TextColumn get nit => text()();
  TextColumn get email => text()();
  TextColumn get bankAccount => text()();
  BoolColumn get showPhone => boolean()();
  BoolColumn get showNit => boolean()();
  BoolColumn get showEmail => boolean()();
  BoolColumn get showBankAccount => boolean()();
  IntColumn get mora => integer().withDefault(const Constant(20))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MoraRow')
class Mora extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cardId => text().references(CardsTable, #id)();
  BoolColumn get pagado => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

class MoraTracking extends Table {
  TextColumn get cardId => text()();
  DateTimeColumn get lastCheckedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {cardId};
}

class MoraApplications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get paymentId => text().references(Payments, #id)();
  IntColumn get moraId => integer().references(Mora, #id)();
  IntColumn get cents => integer()();
  BoolColumn get reversed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get reversedAt => dateTime().nullable()();
}

class PaymentChanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get paymentId => text().references(Payments, #id)();
  RealColumn get oldAmount => real()();
  RealColumn get newAmount => real()();
  IntColumn get oldMoraCents => integer()();
  IntColumn get newMoraCents => integer()();
  DateTimeColumn get oldScheduledDate => dateTime().nullable()();
  DateTimeColumn get newScheduledDate => dateTime().nullable()();
  TextColumn get oldType => text()();
  TextColumn get newType => text()();
  TextColumn get oldReceipt => text().nullable()();
  TextColumn get newReceipt => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(
  tables: [
    SyncMetadata,
    Payments,
    ClientsTable,
    ClientPhones,
    CardsTable,
    EnterpriseConfigs,
    Mora,
    MoraTracking,
    MoraApplications,
    PaymentChanges,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 10;

  Future<void> savePayments(List<PaymentsCompanion> payments) {
    return batch((batch) {
      batch.insertAll(this.payments, payments);
    });
  }

  Stream<List<Payment>> watchPayments(String cardId) {
    return (select(payments)
          ..where((payment) => payment.cardId.equals(cardId))
          ..orderBy([
            (payment) => OrderingTerm.asc(payment.isManual),
            (payment) => OrderingTerm.asc(payment.position),
            (payment) => OrderingTerm.asc(payment.scheduledDate),
            (payment) => OrderingTerm.asc(payment.id),
          ]))
        .watch();
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
    onCreate: (Migrator migrator) async {
      await migrator.createAll();
      await _createMoraIndex();
      await _setMoraBaseline();
    },
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 2) {
        await migrator.createTable(payments);
      }
      if (from >= 2 && from < 3) {
        await migrator.addColumn(payments, payments.cardId);
      }
      if (from < 4) {
        await migrator.createTable(clientsTable);
        await migrator.createTable(clientPhones);
      }
      if (from < 5) {
        await migrator.createTable(cardsTable);
      }
      if (from < 6) {
        await migrator.createTable(enterpriseConfigs);
      }
      if (from < 7) {
        if (from >= 2) {
          await migrator.alterTable(
            TableMigration(
              payments,
              newColumns: [
                payments.createdAt,
                payments.createdAtEstimated,
                payments.isManual,
                payments.position,
                payments.moraCents,
              ],
            ),
          );
        }
        await customStatement(
          'UPDATE payments SET created_at = scheduled_date, '
          'created_at_estimated = 1 WHERE amount_paid > 0',
        );
      }
      if (from < 8) {
        await migrator.createTable(mora);
        if (from >= 6) {
          await migrator.addColumn(enterpriseConfigs, enterpriseConfigs.mora);
        }
      }
      if (from < 9) {
        await migrator.createTable(moraTracking);
        await migrator.createTable(moraApplications);
        await migrator.createTable(paymentChanges);
        if (from >= 7) {
          await migrator.addColumn(payments, payments.moraCents);
        }
        await _setMoraBaseline();
        await _createMoraIndex();
      }
      if (from < 10) {
        await migrator.addColumn(clientsTable, clientsTable.latitude);
        await migrator.addColumn(clientsTable, clientsTable.longitude);
      }
    },
  );

  Future<void> _createMoraIndex() => customStatement(
    'CREATE UNIQUE INDEX mora_card_day_unique ON mora (card_id, created_at)',
  );

  Future<void> _setMoraBaseline() => into(syncMetadata)
      .insertOnConflictUpdate(
        SyncMetadataCompanion.insert(
          key: 'mora_accrual_baseline_v9',
          lastSyncedAt: Value(DateTime.now()),
        ),
      )
      .then((_) {});
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text().withDefault(const Constant(''))();
  DateTimeColumn get scheduledDate => dateTime().nullable()();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  IntColumn get moraCents => integer().withDefault(const Constant(0))();
  RealColumn get balanceAfter => real()();
  TextColumn get paymentType => text().withDefault(const Constant('cash'))();
  TextColumn get receiptNumber => text().nullable().unique()();
  BoolColumn get isRenewal => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  BoolColumn get createdAtEstimated =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'creditos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
