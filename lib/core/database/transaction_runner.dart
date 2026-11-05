import 'package:injectable/injectable.dart';

import 'app_database.dart';

/// Runs several repository calls inside one local database transaction.
abstract interface class TransactionRunner {
  Future<T> run<T>(Future<T> Function() action);
}

@LazySingleton(as: TransactionRunner)
class DriftTransactionRunner implements TransactionRunner {
  DriftTransactionRunner(this._database);

  final AppDatabase _database;

  @override
  Future<T> run<T>(Future<T> Function() action) =>
      _database.transaction(action);
}
