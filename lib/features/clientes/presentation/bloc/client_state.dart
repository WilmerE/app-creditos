part of 'client_bloc.dart';

enum ClientListStatus { loading, success, failure }

enum ClientSaveStatus { idle, saving, success, failure }

final class ClientState extends Equatable {
  const ClientState({
    this.listStatus = ClientListStatus.loading,
    this.clients = const [],
    this.query = '',
    this.saveStatus = ClientSaveStatus.idle,
    this.message,
  });

  final ClientListStatus listStatus;
  final List<Client> clients;
  final String query;
  final ClientSaveStatus saveStatus;
  final String? message;

  ClientState copyWith({
    ClientListStatus? listStatus,
    List<Client>? clients,
    String? query,
    ClientSaveStatus? saveStatus,
    String? Function()? message,
  }) {
    return ClientState(
      listStatus: listStatus ?? this.listStatus,
      clients: clients ?? this.clients,
      query: query ?? this.query,
      saveStatus: saveStatus ?? this.saveStatus,
      message: message != null ? message() : this.message,
    );
  }

  @override
  List<Object?> get props => [listStatus, clients, query, saveStatus, message];
}
