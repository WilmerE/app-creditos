import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/capital_group.dart';
import '../../domain/use_cases/manage_capital_groups.dart';

class CapitalGroupState {
  const CapitalGroupState({
    this.groups = const [],
    this.loading = true,
    this.error,
  });

  final List<CapitalGroup> groups;
  final bool loading;
  final String? error;
}

class CapitalGroupCubit extends Cubit<CapitalGroupState> {
  CapitalGroupCubit(this._manage) : super(const CapitalGroupState());

  final ManageCapitalGroups _manage;
  StreamSubscription<List<CapitalGroup>>? _subscription;

  void start() {
    _subscription?.cancel();
    _subscription = _manage.watch().listen(
      (groups) => emit(CapitalGroupState(groups: groups, loading: false)),
      onError: (Object error) => emit(
        CapitalGroupState(
          groups: state.groups,
          loading: false,
          error: 'No se pudieron cargar las carpetas de capital.',
        ),
      ),
    );
  }

  Future<void> create({required String name, String? description}) =>
      _manage.create(name: name, description: description);

  Future<void> update({
    required int id,
    required String name,
    String? description,
  }) => _manage.update(id: id, name: name, description: description);

  Future<void> delete(int id) => _manage.delete(id);

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await super.close();
  }
}
