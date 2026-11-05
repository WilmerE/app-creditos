import '../entities/credit_card.dart';
import '../entities/payment_installment.dart';

abstract interface class CreditCardRepository {
  /// Cards of [clientId] that are still open (active, debtor or renewal)
  /// with their pending balance.
  Future<List<CardBalance>> openCardBalances(String clientId);

  /// Ids of the clients with at least one open card whose balance is not Q0.00.
  Future<Set<String>> clientIdsWithPendingBalance();

  Future<bool> hasPreviousCards(String clientId);

  /// Atomically inserts [card] and its schedule, and marks the client's
  /// settled open cards as paid.
  Future<void> createCard(CreditCard card, List<PaymentInstallment> schedule);

  Future<CreditCard?> getCard(String cardId);

  /// Cards of [clientId], newest first.
  Future<List<CreditCard>> cardsForClient(String clientId);

  Stream<List<PaymentInstallment>> watchInstallments(String cardId);

  /// Persists the edited installments (date, amount, balance, type, receipt).
  Future<void> saveInstallments(List<PaymentInstallment> installments);
}
