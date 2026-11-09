import 'package:injectable/injectable.dart';

import '../entities/capital_group.dart';
import '../repositories/capital_group_repository.dart';

@injectable
class ManageCapitalGroups {
  const ManageCapitalGroups(this._repository);

  final CapitalGroupRepository _repository;

  Stream<List<CapitalGroup>> watch() => _repository.watchGroups();

  Future<List<CapitalGroup>> getAll() => _repository.getGroups();

  Future<int> create({required String name, String? description}) =>
      _repository.createGroup(
        name: _requiredName(name),
        description: _cleanDescription(description),
      );

  Future<void> update({
    required int id,
    required String name,
    String? description,
  }) => _repository.updateGroup(
    id: id,
    name: _requiredName(name),
    description: _cleanDescription(description),
  );

  Future<void> delete(int id) => _repository.deleteGroup(id);

  String _requiredName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Escribe un nombre para el grupo.');
    }
    return normalized;
  }

  String? _cleanDescription(String? description) {
    final normalized = description?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
