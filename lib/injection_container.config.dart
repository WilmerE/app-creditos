// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:creditos/core/database/app_database.dart' as _i331;
import 'package:creditos/core/database/transaction_runner.dart' as _i841;
import 'package:creditos/features/capital_groups/data/repositories/drift_capital_group_repository.dart'
    as _i799;
import 'package:creditos/features/capital_groups/domain/repositories/capital_group_repository.dart'
    as _i255;
import 'package:creditos/features/capital_groups/domain/use_cases/manage_capital_groups.dart'
    as _i414;
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
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/credit_card_local_data_source.dart'
    as _i598;
import 'package:creditos/features/cobros_tarjetas/data/datasources/local/payment_local_data_source.dart'
    as _i950;
import 'package:creditos/features/cobros_tarjetas/data/credit_plan_repository.dart'
    as _i704;
import 'package:creditos/features/cobros_tarjetas/data/repositories/credit_card_repository_impl.dart'
    as _i478;
import 'package:creditos/features/cobros_tarjetas/domain/repositories/credit_card_repository.dart'
    as _i112;
import 'package:creditos/features/cobros_tarjetas/domain/use_cases/create_card_with_new_client.dart'
    as _i390;
import 'package:creditos/features/cobros_tarjetas/domain/use_cases/credit_card_creation.dart'
    as _i313;
import 'package:creditos/features/cobros_tarjetas/presentation/bloc/card_creation_cubit.dart'
    as _i1050;
import 'package:creditos/features/cobros_tarjetas/presentation/bloc/card_detail_cubit.dart'
    as _i839;
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
    gh.lazySingleton<_i704.CreditPlanRepository>(
      () => _i704.CreditPlanRepository(gh<_i331.AppDatabase>()),
    );
    gh.lazySingleton<_i255.CapitalGroupRepository>(
      () => _i799.DriftCapitalGroupRepository(gh<_i331.AppDatabase>()),
    );
    gh.lazySingleton<_i841.TransactionRunner>(
      () => _i841.DriftTransactionRunner(gh<_i331.AppDatabase>()),
    );
    gh.lazySingleton<_i950.PaymentLocalDataSource>(
      () => appModule.paymentLocalDataSource(gh<_i331.AppDatabase>()),
    );
    gh.lazySingleton<_i770.ClientLocalDataSource>(
      () => _i770.ClientLocalDataSource(gh<_i331.AppDatabase>()),
    );
    gh.lazySingleton<_i598.CreditCardLocalDataSource>(
      () => _i598.CreditCardLocalDataSource(gh<_i331.AppDatabase>()),
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
    gh.factory<_i414.ManageCapitalGroups>(
      () => _i414.ManageCapitalGroups(gh<_i255.CapitalGroupRepository>()),
    );
    gh.lazySingleton<_i112.CreditCardRepository>(
      () => _i478.CreditCardRepositoryImpl(
        gh<_i598.CreditCardLocalDataSource>(),
        gh<_i950.PaymentLocalDataSource>(),
      ),
    );
    gh.factory<_i839.CardDetailCubit>(
      () => _i839.CardDetailCubit(
        gh<_i112.CreditCardRepository>(),
        gh<_i743.ClientRepository>(),
      ),
    );
    gh.factory<_i313.CreditCardCreation>(
      () => _i313.CreditCardCreation(gh<_i112.CreditCardRepository>()),
    );
    gh.factory<_i390.CreateCardWithNewClient>(
      () => _i390.CreateCardWithNewClient(
        gh<_i743.ClientRepository>(),
        gh<_i313.CreditCardCreation>(),
        gh<_i841.TransactionRunner>(),
      ),
    );
    gh.factory<_i1050.CardCreationCubit>(
      () => _i1050.CardCreationCubit(
        gh<_i743.ClientRepository>(),
        gh<_i313.CreditCardCreation>(),
        gh<_i390.CreateCardWithNewClient>(),
        capitalGroupRepository: gh<_i255.CapitalGroupRepository>(),
        planRepository: gh<_i704.CreditPlanRepository>(),
      ),
    );
    return this;
  }
}

class _$AppModule extends _i568.AppModule {}
