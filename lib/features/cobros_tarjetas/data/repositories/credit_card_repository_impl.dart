import 'package:injectable/injectable.dart';

import '../../domain/entities/credit_card.dart';
import '../../domain/entities/payment_installment.dart';
import '../../domain/repositories/credit_card_repository.dart';
import '../datasources/local/credit_card_local_data_source.dart';
import '../datasources/local/payment_local_data_source.dart';

@LazySingleton(as: CreditCardRepository)
class CreditCardRepositoryImpl implements CreditCardRepository {
  CreditCardRepositoryImpl(this._local, this._payments);

  final CreditCardLocalDataSource _local;
  final PaymentLocalDataSource _payments;

  @override
  Future<List<CardBalance>> openCardBalances(String clientId) =>
      _local.openCardBalances(clientId);

  @override
  Future<Set<String>> clientIdsWithPendingBalance() =>
      _local.clientIdsWithPendingBalance();

  @override
  Future<bool> hasPreviousCards(String clientId) =>
      _local.hasPreviousCards(clientId);

  @override
  Future<void> createCard(CreditCard card, List<PaymentInstallment> schedule) =>
      _local.createCard(card, schedule);

  @override
  Future<CreditCard?> getCard(String cardId) => _local.getCard(cardId);

  @override
  Future<List<CreditCard>> cardsForClient(String clientId) =>
      _local.cardsForClient(clientId);

  @override
  Stream<List<PaymentInstallment>> watchInstallments(String cardId) =>
      _payments.watchInstallmentsByCard(cardId);

  @override
  Future<void> saveInstallments(List<PaymentInstallment> installments) =>
      _payments.updateInstallments(installments);
}
