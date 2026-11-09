import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/enterprise_config.dart';

class EnterpriseConfigRepository {
  EnterpriseConfigRepository(this._database);

  final AppDatabase _database;

  Stream<EnterpriseConfig> watch() =>
      (_database.select(
        _database.enterpriseConfigs,
      )..where((row) => row.id.equals(1))).watchSingleOrNull().map(
        (row) => row == null
            ? const EnterpriseConfig()
            : EnterpriseConfig(
                name: row.name,
                phone: row.phone,
                nit: row.nit,
                email: row.email,
                bankAccount: row.bankAccount,
                showPhone: row.showPhone,
                showNit: row.showNit,
                showEmail: row.showEmail,
                showBankAccount: row.showBankAccount,
                mora: row.mora,
                collectionDeadlineHour: row.collectionDeadlineHour,
                collectionDeadlineMinute: row.collectionDeadlineMinute,
                collectionReminderMinutes: row.collectionReminderMinutes,
              ),
      );

  Future<void> save(EnterpriseConfig config) {
    if (config.mora <= 0) {
      throw ArgumentError.value(
        config.mora,
        'mora',
        'Debe ser mayor que cero.',
      );
    }
    if (config.collectionDeadlineHour < 0 ||
        config.collectionDeadlineHour > 23 ||
        config.collectionDeadlineMinute < 0 ||
        config.collectionDeadlineMinute > 59 ||
        config.collectionReminderMinutes < 1 ||
        config.collectionReminderMinutes > 720) {
      throw ArgumentError('Revise el límite diario y el tiempo de aviso.');
    }
    return _database
        .into(_database.enterpriseConfigs)
        .insertOnConflictUpdate(
          EnterpriseConfigsCompanion.insert(
            id: const Value(1),
            name: config.name,
            phone: config.phone,
            nit: config.nit,
            email: config.email,
            bankAccount: config.bankAccount,
            showPhone: config.showPhone,
            showNit: config.showNit,
            showEmail: config.showEmail,
            showBankAccount: config.showBankAccount,
            mora: Value(config.mora),
            collectionDeadlineHour: Value(config.collectionDeadlineHour),
            collectionDeadlineMinute: Value(config.collectionDeadlineMinute),
            collectionReminderMinutes: Value(config.collectionReminderMinutes),
          ),
        );
  }
}
