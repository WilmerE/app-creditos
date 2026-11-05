import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class LocalStorageFailure extends Failure {
  const LocalStorageFailure(super.message);
}

final class RemoteServiceFailure extends Failure {
  const RemoteServiceFailure(super.message);
}
