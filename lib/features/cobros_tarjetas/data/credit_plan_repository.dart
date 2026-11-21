import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/entities/credit_plan.dart';

@lazySingleton
class CreditPlanRepository {
  const CreditPlanRepository(this._database);

  final AppDatabase _database;

  /// Drift does not track raw SQL writes; announce them so sync notices.
  static const tableUpdate = TableUpdate('credit_plans');

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  void _notify() => _database.notifyUpdates({tableUpdate});

  Future<List<CreditPlan>> getAll() async {
    final rows = await _database
        .customSelect(
          'SELECT id, amount_cents, installments, installment_cents, is_active '
          'FROM credit_plans WHERE deleted_at IS NULL '
          'ORDER BY amount_cents, installments, installment_cents',
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
    final now = _nowSeconds();
    if (plan.id == null) {
      // Deleted plans stay as tombstones for sync; re-creating the same plan
      // revives the tombstone instead of violating the uniqueness rule.
      final revived = await _database.customUpdate(
        'UPDATE credit_plans SET is_active = ?, deleted_at = NULL, '
        'updated_at = ? WHERE amount_cents = ? AND installments = ? '
        'AND installment_cents = ? AND deleted_at IS NOT NULL',
        variables: [
          Variable.withInt(plan.isActive ? 1 : 0),
          Variable.withInt(now),
          Variable.withInt(amountCents),
          Variable.withInt(plan.installments),
          Variable.withInt(installmentCents),
        ],
      );
      if (revived == 0) {
        await _database.customUpdate(
          'INSERT INTO credit_plans '
          '(amount_cents, installments, installment_cents, is_active, '
          'sync_id, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withInt(amountCents),
            Variable.withInt(plan.installments),
            Variable.withInt(installmentCents),
            Variable.withInt(plan.isActive ? 1 : 0),
            Variable.withString(const Uuid().v4()),
            Variable.withInt(now),
          ],
        );
      }
      _notify();
      return;
    }
    // An edit that lands on a deleted plan's values replaces that tombstone.
    await _database.customUpdate(
      'DELETE FROM credit_plans WHERE amount_cents = ? AND installments = ? '
      'AND installment_cents = ? AND deleted_at IS NOT NULL AND id <> ?',
      variables: [
        Variable.withInt(amountCents),
        Variable.withInt(plan.installments),
        Variable.withInt(installmentCents),
        Variable.withInt(plan.id!),
      ],
    );
    await _database.customUpdate(
      'UPDATE credit_plans SET amount_cents = ?, installments = ?, '
      'installment_cents = ?, is_active = ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(amountCents),
        Variable.withInt(plan.installments),
        Variable.withInt(installmentCents),
        Variable.withInt(plan.isActive ? 1 : 0),
        Variable.withInt(now),
        Variable.withInt(plan.id!),
      ],
    );
    _notify();
  }

  Future<void> setActive(int id, bool isActive) async {
    await _database.customUpdate(
      'UPDATE credit_plans SET is_active = ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(isActive ? 1 : 0),
        Variable.withInt(_nowSeconds()),
        Variable.withInt(id),
      ],
    );
    _notify();
  }

  Future<void> delete(int id) async {
    await _database.customUpdate(
      'UPDATE credit_plans SET deleted_at = ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(_nowSeconds()),
        Variable.withInt(_nowSeconds()),
        Variable.withInt(id),
      ],
    );
    _notify();
  }
}
