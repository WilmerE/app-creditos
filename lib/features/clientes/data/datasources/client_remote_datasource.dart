import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/client.dart';

/// Per-client remote contract retained for focused use cases. Whole-database
/// push/pull orchestration lives in `core/network/supabase_delta_sync.dart`.
abstract interface class ClientRemoteDataSource {
  Future<void> upsertClients(List<Client> clients);

  Future<List<Client>> fetchChangedSince(DateTime? since);
}

class SupabaseClientRemoteDataSource implements ClientRemoteDataSource {
  const SupabaseClientRemoteDataSource(this._client);

  final SupabaseClient _client;

  static const _table = 'clients';

  @override
  Future<void> upsertClients(List<Client> clients) async {
    if (clients.isEmpty) return;
    await _client
        .from(_table)
        .upsert(clients.map(_toJson).toList(growable: false));
  }

  @override
  Future<List<Client>> fetchChangedSince(DateTime? since) async {
    var query = _client.from(_table).select();
    if (since != null) {
      query = query.gt('updated_at', since.toUtc().toIso8601String());
    }
    final rows = await query;
    return rows.map(_fromJson).toList(growable: false);
  }

  Map<String, Object?> _toJson(Client client) => {
    'id': client.id,
    'full_name': client.fullName,
    'address': client.address,
    'phones': client.phones,
    'dpi': client.dpi,
    'dpi_folder': client.dpiFolder,
    'alias': client.alias,
    'created_at': client.createdAt.toUtc().toIso8601String(),
    'updated_at': client.updatedAt.toUtc().toIso8601String(),
  };

  Client _fromJson(Map<String, dynamic> json) => Client(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    address: json['address'] as String,
    phones: List<String>.from(json['phones'] as List? ?? const []),
    dpi: json['dpi'] as String?,
    dpiFolder: json['dpi_folder'] as String?,
    alias: json['alias'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
