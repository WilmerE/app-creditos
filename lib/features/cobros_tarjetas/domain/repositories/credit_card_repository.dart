import '../entities/credit_card.dart';
import '../entities/payment_installment.dart';

abstract interface class CreditCardRepository {
  /// Cards of [clientId] that are still open (active, debtor or renewal)
  /// with their pending balance.
  Future<List<CardBalance>> openCardBalances(String clientId);

  Future<bool> hasPreviousCards(String clientId);

  /// Atomically inserts [card] and its schedule, and marks the client's
  /// settled open cards as paid.
  Future<void> createCard(CreditCard card, List<PaymentInstallment> schedule);
}
