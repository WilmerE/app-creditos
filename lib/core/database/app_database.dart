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

@DriftDatabase(tables: [SyncMetadata, Payments, ClientsTable, ClientPhones])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  Future<void> savePayments(List<PaymentsCompanion> payments) {
    return batch((batch) {
      batch.insertAllOnConflictUpdate(this.payments, payments);
    });
  }

  Stream<List<Payment>> watchPayments(String cardId) {
    return (select(payments)
          ..where((payment) => payment.cardId.equals(cardId))
          ..orderBy([(payment) => OrderingTerm.asc(payment.scheduledDate)]))
        .watch();
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) => migrator.createAll(),
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
    },
  );
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text().withDefault(const Constant(''))();
  DateTimeColumn get scheduledDate => dateTime()();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  RealColumn get balanceAfter => real()();
  TextColumn get paymentType => text().withDefault(const Constant('cash'))();
  TextColumn get receiptNumber => text().nullable().unique()();
  BoolColumn get isRenewal => boolean().withDefault(const Constant(false))();
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
