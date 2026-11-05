part of 'client_bloc.dart';

sealed class ClientEvent extends Equatable {
  const ClientEvent();

  @override
  List<Object?> get props => [];
}

final class ClientsSubscriptionRequested extends ClientEvent {
  const ClientsSubscriptionRequested();
}

final class ClientSearchChanged extends ClientEvent {
  const ClientSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

final class _ClientsChanged extends ClientEvent {
  const _ClientsChanged(this.clients);

  final List<Client> clients;

  @override
  List<Object?> get props => [clients];
}

final class _ClientsFailed extends ClientEvent {
  const _ClientsFailed(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class ClientSaved extends ClientEvent {
  const ClientSaved(this.client, {this.newPhotoSourcePath});

  final Client client;
  final String? newPhotoSourcePath;

  @override
  List<Object?> get props => [client, newPhotoSourcePath];
}

final class ClientDeleted extends ClientEvent {
  const ClientDeleted(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class ClientMessageCleared extends ClientEvent {
  const ClientMessageCleared();
}
