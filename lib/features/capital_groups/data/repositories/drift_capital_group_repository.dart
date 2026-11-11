import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

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
            ..where((group) => group.deletedAt.isNull())
            ..orderBy([(group) => OrderingTerm.asc(group.name)]))
          .watch()
          .map((rows) => rows.map(_toEntity).toList(growable: false));

  @override
  Future<List<CapitalGroup>> getGroups() async =>
      (_database.select(_database.capitalGroups)
            ..where((group) => group.deletedAt.isNull())
            ..orderBy([(group) => OrderingTerm.asc(group.name)]))
          .map(_toEntity)
          .get();

  @override
  Future<int> createGroup({required String name, String? description}) =>
      _database
          .into(_database.capitalGroups)
          .insert(
            CapitalGroupsCompanion.insert(
              syncId: Value(const Uuid().v4()),
              name: name,
              description: Value(description),
              createdAt: DateTime.now(),
              updatedAt: Value(DateTime.now()),
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
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (updated == 0) throw StateError('La carpeta de capital ya no existe.');
  }

  @override
  Future<void> deleteGroup(int id) async {
    await _database.transaction(() async {
      final now = DateTime.now();
      final deleted =
          await (_database.update(_database.capitalGroups)..where(
                (group) => group.id.equals(id) & group.deletedAt.isNull(),
              ))
              .write(
                CapitalGroupsCompanion(
                  deletedAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
      if (deleted == 0) {
        throw StateError('La carpeta de capital ya no existe.');
      }
      await (_database.update(
        _database.cardsTable,
      )..where((card) => card.folderId.equals(id))).write(
        CardsTableCompanion(folderId: const Value(null), updatedAt: Value(now)),
      );
    });
  }

  CapitalGroup _toEntity(CapitalGroupRow row) => CapitalGroup(
    id: row.id,
    name: row.name,
    description: row.description,
    createdAt: row.createdAt,
  );
}
