import 'dart:io';

import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/features/enterprise/data/enterprise_config_repository.dart';
import 'package:creditos/features/enterprise/domain/enterprise_config.dart';
import 'package:creditos/features/enterprise/presentation/enterprise_config_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits and saves the enterprise header settings', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = EnterpriseConfigRepository(db);
    await tester.pumpWidget(
      MaterialApp(home: EnterpriseConfigScreen(repository: repository)),
    );
    await tester.runAsync(() async {
      await repository.watch().first;
    });
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre de la empresa'),
      'Empresa Nueva',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'NIT'),
      'NIT-123',
    );
    await tester.tap(find.text('Mostrar NIT en la tarjeta'));
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => repository.watch().first);
    expect(saved, isNotNull);
    expect(saved!.name, 'Empresa Nueva');
    expect(saved.nit, 'NIT-123');
    expect(saved.showNit, isTrue);
    expect(find.text('Configuración guardada.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test(
    'persists all fields and display choices across database reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'enterprise_config_test_',
      );
      final file = File('${directory.path}/test.sqlite');
      addTearDown(() => directory.delete(recursive: true));
      var db = AppDatabase.forTesting(NativeDatabase(file));
      final repository = EnterpriseConfigRepository(db);
      expect((await repository.watch().first).name, 'V&\$ INVERSIONES');
      await repository.save(
        const EnterpriseConfig(
          name: 'Empresa',
          phone: '12345678',
          nit: '123-K',
          email: 'empresa@example.com',
          bankAccount: '987',
          showPhone: true,
          showNit: false,
          showEmail: true,
          showBankAccount: false,
        ),
      );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      final saved = await EnterpriseConfigRepository(db).watch().first;
      expect(
        [saved.name, saved.phone, saved.nit, saved.email, saved.bankAccount],
        ['Empresa', '12345678', '123-K', 'empresa@example.com', '987'],
      );
      expect(
        [
          saved.showPhone,
          saved.showNit,
          saved.showEmail,
          saved.showBankAccount,
        ],
        [true, false, true, false],
      );
      await db.close();
    },
  );

  test('migrates a version 5 database without losing existing data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'enterprise_migration_test_',
    );
    final file = File('${directory.path}/test.sqlite');
    addTearDown(() => directory.delete(recursive: true));
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await db.customStatement(
      "INSERT INTO sync_metadata (key) VALUES ('preserved')",
    );
    await db.customStatement('DROP TABLE enterprise_configs');
    await db.customStatement('DROP TABLE mora');
    await db.customStatement('DROP TABLE mora_tracking');
    await db.customStatement('DROP TABLE mora_applications');
    await db.customStatement('DROP TABLE payment_changes');
    await db.customStatement('ALTER TABLE payments DROP COLUMN mora_cents');
    await db.customStatement('PRAGMA user_version = 5');
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    expect(
      (await db.select(db.syncMetadata).get()).any(
        (row) => row.key == 'preserved',
      ),
      isTrue,
    );
    final repository = EnterpriseConfigRepository(db);
    await repository.save(const EnterpriseConfig(name: 'Migrada'));
    expect((await repository.watch().first).name, 'Migrada');
    await db.close();
  });
}
