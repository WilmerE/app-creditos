import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../core/database/app_database.dart';
import '../domain/entities/credit_plan.dart';

@lazySingleton
class CreditPlanRepository {
  const CreditPlanRepository(this._database);

  final AppDatabase _database;

  Future<List<CreditPlan>> getAll() async {
    final rows = await _database
        .customSelect(
          'SELECT id, amount_cents, installments, installment_cents, is_active '
          'FROM credit_plans ORDER BY amount_cents, installments, installment_cents',
        )
        .get();
    return rows
        .map(
          (row) => CreditPlan(
            id: row.read<int>('id'),
            amount: row.read<int>('amount_cents') / 100,
            installments: row.read<int>('installments'),
            installmentAmount: row.read<int>('installment_cents') / 100,
            isActive: row.read<int>('is_active') == 1,
          ),
        )
        .toList(growable: false);
  }

  Future<List<CreditPlan>> getActive() async =>
      (await getAll()).where((plan) => plan.isActive).toList(growable: false);

  Future<void> save(CreditPlan plan) async {
    final amountCents = (plan.amount * 100).round();
    final installmentCents = (plan.installmentAmount * 100).round();
    if (plan.id == null) {
      await _database.customStatement(
        'INSERT INTO credit_plans '
        '(amount_cents, installments, installment_cents, is_active) '
        'VALUES (?, ?, ?, ?)',
        [
          Variable.withInt(amountCents),
          Variable.withInt(plan.installments),
          Variable.withInt(installmentCents),
          Variable.withInt(plan.isActive ? 1 : 0),
        ],
      );
      return;
    }
    await _database.customStatement(
      'UPDATE credit_plans SET amount_cents = ?, installments = ?, '
      'installment_cents = ?, is_active = ? WHERE id = ?',
      [
        Variable.withInt(amountCents),
        Variable.withInt(plan.installments),
        Variable.withInt(installmentCents),
        Variable.withInt(plan.isActive ? 1 : 0),
        Variable.withInt(plan.id!),
      ],
    );
  }

  Future<void> setActive(int id, bool isActive) async {
    await _database.customStatement(
      'UPDATE credit_plans SET is_active = ? WHERE id = ?',
      [Variable.withInt(isActive ? 1 : 0), Variable.withInt(id)],
    );
  }

  Future<void> delete(int id) async {
    await _database.customStatement(
      'DELETE FROM credit_plans WHERE id = ?',
      [Variable.withInt(id)],
    );
  }
}
