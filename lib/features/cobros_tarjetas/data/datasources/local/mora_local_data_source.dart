import 'package:drift/drift.dart';

import '../../../../../core/database/app_database.dart';
import '../../../domain/entities/credit_card.dart';

class MoraLocalDataSource {
  const MoraLocalDataSource(this.db);

  final AppDatabase db;

  static DateTime _day(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  Future<void> accrue(String cardId, {DateTime? now}) async {
    final today = _day(now ?? DateTime.now());
    final card = await (db.select(
      db.cardsTable,
    )..where((row) => row.id.equals(cardId))).getSingle();
    final tracking = await (db.select(
      db.moraTracking,
    )..where((row) => row.cardId.equals(cardId))).getSingleOrNull();
    final baseline = await (db.select(
      db.syncMetadata,
    )..where((row) => row.key.equals('mora_accrual_baseline_v9'))).getSingle();
    final last = _day(
      tracking?.lastCheckedAt ??
          (card.createdAt.isAfter(baseline.lastSyncedAt!)
              ? card.createdAt
              : baseline.lastSyncedAt!),
    );
    if (today.isBefore(last)) {
      throw StateError(
        'El reloj del dispositivo es anterior al último cálculo de mora.',
      );
    }

    final payments = await (db.select(
      db.payments,
    )..where((row) => row.cardId.equals(cardId))).get();
    final principalPaid = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.amountPaid - payment.moraCents / 100,
    );
    final isOpen = CardStatus.values.byName(card.status).isOpen;
    DateTime? oldest;
    if (isOpen &&
        card.totalInstallments * card.weeklyAmount - principalPaid > 0.005) {
      for (final payment in payments) {
        final date = payment.scheduledDate;
        if (payment.isManual ||
            date == null ||
            payment.amountPaid - payment.moraCents / 100 >=
                card.weeklyAmount - 0.005) {
          continue;
        }
        final due = _day(date);
        if (oldest == null || due.isBefore(oldest)) oldest = due;
      }
    }
    if (oldest != null) {
      final existing = await (db.select(
        db.mora,
      )..where((row) => row.cardId.equals(cardId))).get();
      final days = existing.map((row) => _day(row.createdAt)).toSet();
      var day = DateTime(last.year, last.month, last.day + 1);
      while (!day.isAfter(today)) {
        if (day.isAfter(oldest) && days.add(day)) {
          await db
              .into(db.mora)
              .insert(MoraCompanion.insert(cardId: cardId, createdAt: day));
        }
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    await db
        .into(db.moraTracking)
        .insertOnConflictUpdate(
          MoraTrackingCompanion.insert(cardId: cardId, lastCheckedAt: today),
        );
  }

  Future<int> dailyRate() async {
    final config = await (db.select(
      db.enterpriseConfigs,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    return config?.mora ?? 20;
  }

  Future<List<MoraRow>> pending(String cardId) =>
      (db.select(db.mora)
            ..where(
              (row) => row.cardId.equals(cardId) & row.pagado.equals(false),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.id),
            ]))
          .get();
}
