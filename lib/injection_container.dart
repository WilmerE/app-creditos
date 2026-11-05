import 'package:injectable/injectable.dart';
import 'package:get_it/get_it.dart';

import 'core/database/app_database.dart';
import 'injection_container.config.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {
  getIt.init();

  // Open the local database before the UI starts so initialization failures
  // are not hidden behind a successful-looking offline screen.
  await getIt<AppDatabase>().customSelect('SELECT 1').get();
}

@module
abstract class AppModule {
  @lazySingleton
  AppDatabase get database => AppDatabase();
}
