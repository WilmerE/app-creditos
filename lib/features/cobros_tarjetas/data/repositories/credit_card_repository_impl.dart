import 'package:injectable/injectable.dart';

import '../../domain/entities/credit_card.dart';
import '../../domain/entities/payment_installment.dart';
import '../../domain/repositories/credit_card_repository.dart';
import '../datasources/local/credit_card_local_data_source.dart';

@LazySingleton(as: CreditCardRepository)
class CreditCardRepositoryImpl implements CreditCardRepository {
  CreditCardRepositoryImpl(this._local);

  final CreditCardLocalDataSource _local;

  @override
  Future<List<CardBalance>> openCardBalances(String clientId) =>
      _local.openCardBalances(clientId);

  @override
  Future<bool> hasPreviousCards(String clientId) =>
      _local.hasPreviousCards(clientId);

  @override
  Future<void> createCard(CreditCard card, List<PaymentInstallment> schedule) =>
      _local.createCard(card, schedule);
}
