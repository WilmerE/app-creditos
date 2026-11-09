import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/capital_group.dart';
import '../../domain/repositories/capital_group_repository.dart';

@LazySingleton(as: CapitalGroupRepository)
class DriftCapitalGroupRepository implements CapitalGroupRepository {
  const DriftCapitalGroupRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<CapitalGroup>> watchGroups() =>
      (_database.select(_database.capitalGroups)
            ..orderBy([(group) => OrderingTerm.asc(group.name)]))
          .watch()
          .map((rows) => rows.map(_toEntity).toList(growable: false));

  @override
  Future<List<CapitalGroup>> getGroups() async => (_database.select(
    _database.capitalGroups,
  )..orderBy([(group) => OrderingTerm.asc(group.name)])).map(_toEntity).get();

  @override
  Future<int> createGroup({required String name, String? description}) =>
      _database
          .into(_database.capitalGroups)
          .insert(
            CapitalGroupsCompanion.insert(
              name: name,
              description: Value(description),
              createdAt: DateTime.now(),
            ),
          );

  @override
  Future<void> updateGroup({
    required int id,
    required String name,
    String? description,
  }) async {
    final updated =
        await (_database.update(
          _database.capitalGroups,
        )..where((group) => group.id.equals(id))).write(
          CapitalGroupsCompanion(
            name: Value(name),
            description: Value(description),
          ),
        );
    if (updated == 0) throw StateError('La carpeta de capital ya no existe.');
  }

  @override
  Future<void> deleteGroup(int id) async {
    final deleted = await (_database.delete(
      _database.capitalGroups,
    )..where((group) => group.id.equals(id))).go();
    if (deleted == 0) throw StateError('La carpeta de capital ya no existe.');
  }

  CapitalGroup _toEntity(CapitalGroupRow row) => CapitalGroup(
    id: row.id,
    name: row.name,
    description: row.description,
    createdAt: row.createdAt,
  );
}
