import 'package:creditos/features/cobros_tarjetas/domain/entities/credit_card.dart';
import 'package:creditos/features/cobros_tarjetas/domain/entities/payment_installment.dart';
import 'package:creditos/features/cobros_tarjetas/presentation/bloc/card_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the detail separates paid mora from capital and uses the configured rate',
    () {
      final card = CreditCard(
        id: 'card',
        clientId: 'client',
        requestedAmount: 300,
        deliveredAmount: 300,
        totalInstallments: 3,
        weeklyAmount: 100,
        status: CardStatus.active,
        colorHex: '#000000',
        startDate: DateTime(2026),
        createdAt: DateTime(2026),
      );
      final state = CardDetailState(
        card: card,
        installments: [
          PaymentInstallment(
            id: 'a',
            cardId: 'card',
            scheduledDate: DateTime(2026),
            amountPaid: 60,
            moraCents: 4000,
            balanceAfter: 280,
          ),
        ],
        lateFee: const LateFee(days: 2, rate: 30),
      );
      expect(state.totalPaid, 20);
      expect(state.pendingBalance, 280);
      expect(state.lateFee.amount, 60);
      expect(state.totalDueToday, 340);
    },
  );
}
