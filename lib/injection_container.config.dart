// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:creditos/core/database/app_database.dart' as _i331;
import 'package:creditos/features/clientes/data/datasources/client_local_datasource.dart'
    as _i770;
import 'package:creditos/features/clientes/data/repositories/client_repository_impl.dart'
    as _i806;
import 'package:creditos/features/clientes/data/services/client_photo_storage.dart'
    as _i915;
import 'package:creditos/features/clientes/domain/repositories/client_repository.dart'
    as _i743;
import 'package:creditos/features/clientes/presentation/bloc/client_bloc.dart'
    as _i858;
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart'
    as _i950;
import 'package:creditos/injection_container.dart' as _i568;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final appModule = _$AppModule();
    gh.lazySingleton<_i915.ClientPhotoStorage>(
      () => _i915.ClientPhotoStorage(),
    );
    gh.lazySingleton<_i331.AppDatabase>(() => appModule.database);
    gh.lazySingleton<_i950.PaymentLocalDataSource>(
      () => appModule.paymentLocalDataSource(gh<_i331.AppDatabase>()),
    );
    gh.lazySingleton<_i770.ClientLocalDataSource>(
      () => _i770.ClientLocalDataSource(gh<_i331.AppDatabase>()),
    );
    gh.lazySingleton<_i743.ClientRepository>(
      () => _i806.ClientRepositoryImpl(
        gh<_i770.ClientLocalDataSource>(),
        gh<_i915.ClientPhotoStorage>(),
      ),
    );
    gh.factory<_i858.ClientBloc>(
      () => _i858.ClientBloc(gh<_i743.ClientRepository>()),
    );
    return this;
  }
}

class _$AppModule extends _i568.AppModule {}
