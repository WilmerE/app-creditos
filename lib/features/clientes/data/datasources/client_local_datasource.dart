import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/client.dart';

@lazySingleton
class ClientLocalDataSource {
  ClientLocalDataSource(this._database);

  final AppDatabase _database;

  $ClientsTableTable get _clients => _database.clientsTable;
  $ClientPhonesTable get _phones => _database.clientPhones;

  Stream<List<Client>> watchClients({String query = ''}) {
    return _buildQuery(query).watch().map(_groupRows);
  }

  Future<List<Client>> findClients({String query = ''}) async {
    return _groupRows(await _buildQuery(query).get());
  }

  Future<Client?> getById(String id) async {
    final query = _database.select(_clients).join([
      leftOuterJoin(_phones, _phones.clientId.equalsExp(_clients.id)),
    ])..where(_clients.id.equals(id));
    final clients = _groupRows(await query.get());
    return clients.isEmpty ? null : clients.single;
  }

  Future<void> insert(Client client) {
    return _database.transaction(() async {
      await _database.into(_clients).insert(_toCompanion(client));
      await _insertPhones(client);
    });
  }

  Future<void> update(Client client) {
    return _database.transaction(() async {
      await (_database.update(
        _clients,
      )..where((row) => row.id.equals(client.id))).write(
        ClientsTableCompanion(
          fullName: Value(client.fullName),
          address: Value(client.address),
          dpi: Value(client.dpi),
          dpiFolder: Value(client.dpiFolder),
          alias: Value(client.alias),
          photoPath: Value(client.photoPath),
          updatedAt: Value(client.updatedAt),
        ),
      );
      await (_database.delete(
        _phones,
      )..where((row) => row.clientId.equals(client.id))).go();
      await _insertPhones(client);
    });
  }

  Future<void> softDelete(String id, DateTime deletedAt) {
    return (_database.update(
      _clients,
    )..where((row) => row.id.equals(id))).write(
      ClientsTableCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _buildQuery(String text) {
    final query = _database.select(_clients).join([
      leftOuterJoin(_phones, _phones.clientId.equalsExp(_clients.id)),
    ])..where(_clients.deletedAt.isNull());

    final term = text.trim();
    if (term.isNotEmpty) {
      query.where(
        _clients.fullName.contains(term) |
            _clients.dpi.contains(term) |
            _clients.alias.contains(term),
      );
    }

    query.orderBy([
      OrderingTerm.asc(_clients.fullName.collate(Collate.noCase)),
      OrderingTerm.asc(_phones.position),
    ]);
    return query;
  }

  List<Client> _groupRows(List<TypedResult> rows) {
    final clients = <String, ClientRow>{};
    final phones = <String, List<String>>{};
    for (final row in rows) {
      final client = row.readTable(_clients);
      clients.putIfAbsent(client.id, () => client);
      final phone = row.readTableOrNull(_phones);
      final list = phones.putIfAbsent(client.id, () => []);
      if (phone != null) list.add(phone.phoneNumber);
    }

    return clients.values
        .map(
          (row) => Client(
            id: row.id,
            fullName: row.fullName,
            address: row.address,
            phones: phones[row.id] ?? const [],
            dpi: row.dpi,
            dpiFolder: row.dpiFolder,
            alias: row.alias,
            photoPath: row.photoPath,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  ClientsTableCompanion _toCompanion(Client client) {
    return ClientsTableCompanion.insert(
      id: client.id,
      fullName: client.fullName,
      address: client.address,
      dpi: Value(client.dpi),
      dpiFolder: Value(client.dpiFolder),
      alias: Value(client.alias),
      photoPath: Value(client.photoPath),
      createdAt: client.createdAt,
      updatedAt: client.updatedAt,
    );
  }

  Future<void> _insertPhones(Client client) {
    return _database.batch((batch) {
      batch.insertAll(_phones, [
        for (var index = 0; index < client.phones.length; index++)
          ClientPhonesCompanion.insert(
            clientId: client.id,
            phoneNumber: client.phones[index],
            position: Value(index),
          ),
      ]);
    });
  }
}
