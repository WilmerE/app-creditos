import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/database/app_database.dart';
import 'core/network/supabase_delta_sync.dart';
import 'features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart';
import 'injection_container.config.dart';

final getIt = GetIt.instance;

// Para reactivarlo en una emergencia, cambia a true temporalmente; sigue
// limitado a builds debug por kDebugMode. Devuélvelo a false al terminar.
const bool kEnableEmergencyLocalDataWipe = false;
bool get canUseEmergencyLocalDataWipe =>
    kDebugMode && kEnableEmergencyLocalDataWipe;

@InjectableInit()
Future<void> configureDependencies({SupabaseClient? supabaseClient}) async {
  getIt.init();

  await _initializeDatabaseAndSync(supabaseClient);
}

/// Replaces the complete dependency graph after the debug database reset.
Future<void> resetLocalDatabaseForDebug() async {
  if (!canUseEmergencyLocalDataWipe) {
    throw StateError('El borrado local de emergencia está desactivado.');
  }

  final sync = getIt<SupabaseDeltaSync>();
  final client = sync.client;
  final database = getIt<AppDatabase>();
  final directory = await getApplicationSupportDirectory();
  final databasePath = p.join(directory.path, 'creditos.sqlite');

  sync.dispose();
  await database.close();
  await getIt.reset();

  Object? deleteError;
  StackTrace? deleteStack;
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('$databasePath$suffix');
    try {
      if (await file.exists()) await file.delete();
    } on Object catch (error, stack) {
      deleteError ??= error;
      deleteStack ??= stack;
    }
  }

  getIt.init();
  await _initializeDatabaseAndSync(client, startSync: false);
  if (deleteError != null) Error.throwWithStackTrace(deleteError, deleteStack!);
}

Future<void> _initializeDatabaseAndSync(
  SupabaseClient? supabaseClient, {
  bool startSync = true,
}) async {
  // Open the local database before the UI starts so initialization failures
  // are not hidden behind a successful-looking offline screen.
  await getIt<AppDatabase>().customSelect('SELECT 1').get();
  getIt.registerSingleton<SupabaseDeltaSync>(
    SupabaseDeltaSync(getIt<AppDatabase>(), supabaseClient),
  );
  if (startSync) getIt<SupabaseDeltaSync>().start();
}

@module
abstract class AppModule {
  @lazySingleton
  AppDatabase get database => AppDatabase();

  @lazySingleton
  PaymentLocalDataSource paymentLocalDataSource(AppDatabase database) {
    return PaymentLocalDataSource(database);
  }
}
