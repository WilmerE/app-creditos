import 'dart:io';

import 'package:creditos/core/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v6 migration preserves payments and labels the estimated reception date',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (database) {
            database.execute(
              'CREATE TABLE sync_metadata (key TEXT NOT NULL PRIMARY KEY, last_synced_at INTEGER)',
            );
            database.execute('''
            CREATE TABLE payments (
              id TEXT NOT NULL PRIMARY KEY,
              card_id TEXT NOT NULL DEFAULT '',
              scheduled_date INTEGER NOT NULL,
              amount_paid REAL NOT NULL DEFAULT 0,
              balance_after REAL NOT NULL,
              payment_type TEXT NOT NULL DEFAULT 'cash',
              receipt_number TEXT UNIQUE,
              is_renewal INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
            )
          ''');
            database.execute(
              "INSERT INTO payments (id, card_id, scheduled_date, amount_paid, balance_after, updated_at) VALUES ('paid', 'card', 1700000000, 25, 75, 1700100000), ('empty', 'card', 1700600000, 0, 75, 1700100000)",
            );
            database.execute('''
              CREATE TABLE enterprise_configs (
                id INTEGER NOT NULL PRIMARY KEY, name TEXT NOT NULL,
                phone TEXT NOT NULL, nit TEXT NOT NULL, email TEXT NOT NULL,
                bank_account TEXT NOT NULL, show_phone INTEGER NOT NULL,
                show_nit INTEGER NOT NULL, show_email INTEGER NOT NULL,
                show_bank_account INTEGER NOT NULL
              )
            ''');
            database.execute('PRAGMA user_version = 6');
          },
        ),
      );
      addTearDown(db.close);
      final rows = await db.select(db.payments).get();
      final paid = rows.firstWhere((row) => row.id == 'paid');
      final empty = rows.firstWhere((row) => row.id == 'empty');
      expect(paid.createdAt, paid.scheduledDate);
      expect(paid.createdAtEstimated, isTrue);
      expect(paid.amountPaid, 25);
      expect(paid.updatedAt.millisecondsSinceEpoch, 1700100000000);
      expect(paid.isManual, isFalse);
      expect(empty.createdAt, isNull);
      expect(empty.createdAtEstimated, isFalse);
    },
  );

  test(
    'v7 migration adds the mora schema without generating historical fees',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (database) {
            database.execute(
              'CREATE TABLE sync_metadata (key TEXT NOT NULL PRIMARY KEY, last_synced_at INTEGER)',
            );
            database.execute(
              'CREATE TABLE payments (id TEXT NOT NULL PRIMARY KEY)',
            );
            database.execute('''
            CREATE TABLE enterprise_configs (
              id INTEGER NOT NULL PRIMARY KEY, name TEXT NOT NULL,
              phone TEXT NOT NULL, nit TEXT NOT NULL, email TEXT NOT NULL,
              bank_account TEXT NOT NULL, show_phone INTEGER NOT NULL,
              show_nit INTEGER NOT NULL, show_email INTEGER NOT NULL,
              show_bank_account INTEGER NOT NULL
            )
          ''');
            database.execute('''
            INSERT INTO enterprise_configs VALUES
              (1, 'Empresa', '', '', '', '', 1, 0, 0, 0)
          ''');
            database.execute('PRAGMA user_version = 7');
          },
        ),
      );
      addTearDown(db.close);

      final config = await db.select(db.enterpriseConfigs).getSingle();
      expect(config.mora, 20);
      expect(await db.select(db.mora).get(), isEmpty);
    },
  );

  test(
    'v8 migration preserves recorded mora, capital payments and configuration',
    () async {
      final directory = await Directory.systemTemp.createTemp('mora_v8_test_');
      final file = File('${directory.path}\\test.sqlite');
      addTearDown(() => directory.delete(recursive: true));
      var db = AppDatabase.forTesting(NativeDatabase(file));
      final now = DateTime.now();
      await db
          .into(db.clientsTable)
          .insert(
            ClientsTableCompanion.insert(
              id: 'c',
              fullName: 'Cliente',
              address: 'Zona',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.cardsTable)
          .insert(
            CardsTableCompanion.insert(
              id: 'card',
              clientId: 'c',
              requestedAmount: 100,
              deliveredAmount: 100,
              totalInstallments: 2,
              weeklyAmount: 50,
              startDate: now,
              createdAt: now,
            ),
          );
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: 'payment',
              cardId: const Value('card'),
              balanceAfter: 75,
              amountPaid: const Value(25),
              createdAt: Value(now),
            ),
          );
      await db
          .into(db.mora)
          .insert(MoraCompanion.insert(cardId: 'card', createdAt: now));
      await db
          .into(db.enterpriseConfigs)
          .insert(
            EnterpriseConfigsCompanion.insert(
              id: const Value(1),
              name: 'Empresa',
              phone: '',
              nit: '',
              email: '',
              bankAccount: '',
              showPhone: false,
              showNit: false,
              showEmail: false,
              showBankAccount: false,
              mora: const Value(35),
            ),
          );
      await db.customStatement('DROP INDEX mora_card_day_unique');
      await db.customStatement('DROP TABLE payment_changes');
      await db.customStatement('DROP TABLE mora_applications');
      await db.customStatement('DROP TABLE mora_tracking');
      await db.customStatement('ALTER TABLE payments DROP COLUMN mora_cents');
      await db.customStatement('PRAGMA user_version = 8');
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      final payment = await db.select(db.payments).getSingle();
      expect(payment.amountPaid, 25);
      expect(payment.moraCents, 0);
      expect((await db.select(db.mora).getSingle()).pagado, isFalse);
      expect((await db.select(db.enterpriseConfigs).getSingle()).mora, 35);
      expect(await db.select(db.moraApplications).get(), isEmpty);
      await db.close();
    },
  );
}
