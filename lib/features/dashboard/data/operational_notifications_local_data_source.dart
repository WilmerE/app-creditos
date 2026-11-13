import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/notifications/local_system_notification_service.dart';

class OperationalNotificationsLocalDataSource {
  const OperationalNotificationsLocalDataSource(this.db);

  final AppDatabase db;

  Stream<List<OperationalNotificationRow>> watch({int? folderId}) {
    final query = db.select(db.operationalNotifications)
      ..where(
        (row) => folderId == null
            ? row.folderId.isNull()
            : row.folderId.equals(folderId),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(50);
    return query.watch();
  }

  Stream<List<OperationalNotificationRow>> watchAll() {
    final query = db.select(db.operationalNotifications)
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch();
  }

  Stream<int> watchUnreadCount() {
    final count = db.operationalNotifications.id.count();
    final query = db.selectOnly(db.operationalNotifications)
      ..addColumns([count])
      ..where(db.operationalNotifications.isRead.equals(false));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  Future<void> add({
    required String eventKey,
    required String type,
    String? cardId,
    int? folderId,
    required String title,
    required String message,
    DateTime? createdAt,
  }) async {
    final existing = await (db.select(
      db.operationalNotifications,
    )..where((row) => row.eventKey.equals(eventKey))).getSingleOrNull();
    if (existing != null) return;
    await db
        .into(db.operationalNotifications)
        .insert(
          OperationalNotificationsCompanion.insert(
            eventKey: eventKey,
            type: type,
            cardId: Value(cardId),
            folderId: Value(folderId),
            title: title,
            message: message,
            createdAt: createdAt ?? DateTime.now(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await LocalSystemNotificationService.instance.show(
      eventKey: eventKey,
      title: title,
      message: message,
    );
  }

  Future<void> evaluateCollectionCutoff({DateTime? now}) async {
    final localNow = (now ?? DateTime.now()).toLocal();
    final config = await (db.select(
      db.enterpriseConfigs,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    final deadline = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      config?.collectionDeadlineHour ?? 18,
      config?.collectionDeadlineMinute ?? 0,
    );
    final reminderStart = deadline.subtract(
      Duration(minutes: config?.collectionReminderMinutes ?? 60),
    );
    if (localNow.isBefore(reminderStart)) return;

    final cards = await db.select(db.cardsTable).get();
    final payments = await db.select(db.payments).get();
    final folderIds = <int?>{null, ...cards.map((card) => card.folderId)};
    for (final folderId in folderIds) {
      final cardIds = cards
          .where(
            (card) =>
                card.folderId == folderId &&
                card.status != 'deactivated' &&
                card.status != 'paid',
          )
          .map((card) => card.id)
          .toSet();
      final count = payments.where((payment) {
        final date = payment.scheduledDate?.toLocal();
        if (date == null ||
            !cardIds.contains(payment.cardId) ||
            payment.isManual) {
          return false;
        }
        if (date.year != localNow.year ||
            date.month != localNow.month ||
            date.day != localNow.day) {
          return false;
        }
        final card = cards.firstWhere((row) => row.id == payment.cardId);
        return payment.amountPaid - payment.moraCents / 100 <
            card.weeklyAmount - 0.005;
      }).length;
      if (count == 0) continue;
      final dateKey =
          '${localNow.year}-${localNow.month.toString().padLeft(2, '0')}-${localNow.day.toString().padLeft(2, '0')}';
      final folderKey = folderId?.toString() ?? 'principal';
      await add(
        eventKey: 'collection_cutoff:$dateKey:$folderKey',
        type: 'collection_cutoff',
        folderId: folderId,
        title: localNow.isBefore(deadline)
            ? 'Se acerca el límite de cobro'
            : 'Cobros pendientes tras el límite',
        message:
            '$count cuota(s) de hoy continúan pendientes. Límite configurado: ${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}.',
        createdAt: localNow,
      );
    }
  }

  Future<void> markRead(int id) =>
      (db.update(db.operationalNotifications)
            ..where((row) => row.id.equals(id)))
          .write(const OperationalNotificationsCompanion(isRead: Value(true)));

  Future<void> markAllRead() =>
      (db.update(db.operationalNotifications)
            ..where((row) => row.isRead.equals(false)))
          .write(const OperationalNotificationsCompanion(isRead: Value(true)));
}
