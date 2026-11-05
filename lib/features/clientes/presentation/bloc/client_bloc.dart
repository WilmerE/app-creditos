import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/client.dart';
import '../../domain/repositories/client_repository.dart';

part 'client_event.dart';
part 'client_state.dart';

@injectable
class ClientBloc extends Bloc<ClientEvent, ClientState> {
  ClientBloc(this._repository) : super(const ClientState()) {
    on<ClientsSubscriptionRequested>(_onSubscribe);
    on<ClientSearchChanged>(_onSearch);
    on<_ClientsChanged>(
      (event, emit) => emit(
        state.copyWith(
          listStatus: ClientListStatus.success,
          clients: event.clients,
        ),
      ),
    );
    on<_ClientsFailed>(
      (event, emit) => emit(
        state.copyWith(
          listStatus: ClientListStatus.failure,
          message: () => event.message,
        ),
      ),
    );
    on<ClientSaved>(_onSaved);
    on<ClientDeleted>(_onDeleted);
    on<ClientMessageCleared>(
      (event, emit) => emit(state.copyWith(message: () => null)),
    );
  }

  final ClientRepository _repository;
  StreamSubscription<List<Client>>? _subscription;

  void _listen(String query) {
    _subscription?.cancel();
    _subscription = _repository
        .watchClients(query: query)
        .listen(
          (clients) => add(_ClientsChanged(clients)),
          onError: (Object _) => add(
            const _ClientsFailed('No se pudo cargar la lista de clientes.'),
          ),
        );
  }

  void _onSubscribe(
    ClientsSubscriptionRequested event,
    Emitter<ClientState> emit,
  ) {
    emit(state.copyWith(listStatus: ClientListStatus.loading));
    _listen(state.query);
  }

  void _onSearch(ClientSearchChanged event, Emitter<ClientState> emit) {
    if (event.query == state.query) return;
    emit(state.copyWith(query: event.query));
    _listen(event.query);
  }

  Future<void> _onSaved(ClientSaved event, Emitter<ClientState> emit) async {
    emit(state.copyWith(saveStatus: ClientSaveStatus.saving));
    try {
      await _repository.save(
        event.client,
        newPhotoSourcePath: event.newPhotoSourcePath,
      );
      emit(state.copyWith(saveStatus: ClientSaveStatus.success));
    } on Object {
      emit(
        state.copyWith(
          saveStatus: ClientSaveStatus.failure,
          message: () => 'No se pudo guardar el cliente. Intente de nuevo.',
        ),
      );
    }
    emit(state.copyWith(saveStatus: ClientSaveStatus.idle));
  }

  Future<void> _onDeleted(
    ClientDeleted event,
    Emitter<ClientState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
    } on Object {
      emit(state.copyWith(message: () => 'No se pudo eliminar el cliente.'));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
