import '../entities/capital_group.dart';

abstract interface class CapitalGroupRepository {
  Stream<List<CapitalGroup>> watchGroups();

  Future<List<CapitalGroup>> getGroups();

  Future<int> createGroup({required String name, String? description});

  Future<void> updateGroup({
    required int id,
    required String name,
    String? description,
  });

  Future<void> deleteGroup(int id);
}
