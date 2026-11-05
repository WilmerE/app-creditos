import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../entities/credit_card.dart';
import '../repositories/credit_card_repository.dart';
import '../services/payment_plan_calculator.dart';

class RenewalBlockedException implements Exception {
  const RenewalBlockedException([
    this.message =
        'El cliente debe liquidar su tarjeta anterior antes de renovar',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Creates a card after enforcing the renewal lock: every previous open card
/// of the client must have a pending balance of Q0.00.
@injectable
class CreditCardCreation {
  const CreditCardCreation(this._repository);

  final CreditCardRepository _repository;

  static const double _epsilon = 0.005;

  Future<bool> isRenewalBlocked(String clientId) async {
    final balances = await _repository.openCardBalances(clientId);
    return balances.any((balance) => balance.pending > _epsilon);
  }

  /// Ids of the clients that still owe money on an open card.
  Future<Set<String>> blockedClientIds() =>
      _repository.clientIdsWithPendingBalance();

  Future<void> ensureCanRenew(String clientId) async {
    if (await isRenewalBlocked(clientId)) throw const RenewalBlockedException();
  }

  /// Returns the id of the created card.
  Future<String> call({
    required String clientId,
    required double requestedAmount,
    required String colorHex,
    PlanOption? option,
    DateTime? startDate,
    DateTime? now,
  }) async {
    await ensureCanRenew(clientId);

    final isRenewal = await _repository.hasPreviousCards(clientId);
    final cardId = const Uuid().v4();
    final plan = PaymentPlanCalculator.calculate(
      requestedAmount: requestedAmount,
      cardId: cardId,
      option: option,
      startDate: startDate,
      now: now,
      isRenewal: isRenewal,
    );

    final card = CreditCard(
      id: cardId,
      clientId: clientId,
      requestedAmount: requestedAmount,
      deliveredAmount: requestedAmount,
      totalInstallments: plan.option.installments,
      weeklyAmount: plan.option.installmentAmount,
      status: isRenewal ? CardStatus.renewal : CardStatus.active,
      colorHex: colorHex,
      startDate: plan.startDate,
      createdAt: now ?? DateTime.now(),
    );
    await _repository.createCard(card, plan.installments);
    return cardId;
  }
}
