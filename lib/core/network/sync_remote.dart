import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The cloud side of the sync, kept narrow so the engine can be exercised
/// against an in-memory store in tests.
abstract interface class SyncRemote {
  /// Every row of [table] visible to the signed-in account.
  Future<List<Map<String, dynamic>>> selectAll(String table);

  /// Inserts or updates [rows], matching existing rows on [onConflict]
  /// (a comma-separated column list).
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows,
    String onConflict,
  );

  Future<void> uploadPhoto(String objectPath, Uint8List bytes);

  Future<Uint8List> downloadPhoto(String objectPath);
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  static const pageSize = 500;
  static const photoBucket = 'client-photos';

  final SupabaseClient _client;

  /// Unique sort key per table. Offset paging without a stable order can
  /// skip or repeat rows once a table spans several pages.
  static const _orderColumns = {
    'clients': 'id',
    'capital_groups': 'sync_id',
    'cards': 'id',
    'payments': 'id',
    'mora': 'sync_id',
    'mora_tracking': 'card_id',
    'mora_applications': 'sync_id',
    'payment_changes': 'sync_id',
    'operational_notifications': 'event_key',
    'credit_plans': 'sync_id',
    'enterprise_configs': 'user_id',
  };

  @override
  Future<List<Map<String, dynamic>>> selectAll(String table) async {
    final orderColumn = _orderColumns[table];
    if (orderColumn == null) {
      throw ArgumentError.value(table, 'table', 'Sin orden de paginación.');
    }
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await _client
          .from(table)
          .select()
          .order(orderColumn, ascending: true)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) return rows;
    }
  }

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows,
    String onConflict,
  ) async {
    for (var offset = 0; offset < rows.length; offset += pageSize) {
      final end = (offset + pageSize).clamp(0, rows.length);
      await _client
          .from(table)
          .upsert(rows.sublist(offset, end), onConflict: onConflict);
    }
  }

  @override
  Future<void> uploadPhoto(String objectPath, Uint8List bytes) async {
    await _client.storage
        .from(photoBucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
  }

  @override
  Future<Uint8List> downloadPhoto(String objectPath) =>
      _client.storage.from(photoBucket).download(objectPath);
}
