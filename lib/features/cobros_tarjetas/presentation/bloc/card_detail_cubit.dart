import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/domain/repositories/client_repository.dart';
import '../../domain/entities/credit_card.dart';
import '../../domain/entities/payment_installment.dart';
import '../../domain/repositories/credit_card_repository.dart';

enum CardDetailStatus { loading, ready, notFound, failure }

class CardDetailState extends Equatable {
  const CardDetailState({
    this.status = CardDetailStatus.loading,
    this.card,
    this.client,
    this.installments = const [],
  });

  final CardDetailStatus status;
  final CreditCard? card;
  final Client? client;
  final List<PaymentInstallment> installments;

  double get totalPaid => installments.fold(0, (sum, i) => sum + i.amountPaid);

  double get pendingBalance => (card?.totalToPay ?? 0) - totalPaid;

  CardDetailState copyWith({
    CardDetailStatus? status,
    CreditCard? card,
    Client? client,
    List<PaymentInstallment>? installments,
  }) {
    return CardDetailState(
      status: status ?? this.status,
      card: card ?? this.card,
      client: client ?? this.client,
      installments: installments ?? this.installments,
    );
  }

  @override
  List<Object?> get props => [status, card, client, installments];
}

@injectable
class CardDetailCubit extends Cubit<CardDetailState> {
  CardDetailCubit(this._cards, this._clients) : super(const CardDetailState());

  final CreditCardRepository _cards;
  final ClientRepository _clients;
  StreamSubscription<List<PaymentInstallment>>? _subscription;

  Future<void> load(String cardId) async {
    emit(const CardDetailState());
    try {
      final card = await _cards.getCard(cardId);
      if (card == null) {
        emit(const CardDetailState(status: CardDetailStatus.notFound));
        return;
      }
      final client = await _clients.getById(card.clientId);
      emit(
        CardDetailState(
          status: client == null
              ? CardDetailStatus.notFound
              : CardDetailStatus.ready,
          card: card,
          client: client,
        ),
      );
      if (client == null) return;

      await _subscription?.cancel();
      _subscription = _cards
          .watchInstallments(cardId)
          .listen(
            (installments) => emit(state.copyWith(installments: installments)),
            onError: (Object _) =>
                emit(state.copyWith(status: CardDetailStatus.failure)),
          );
    } on Object {
      emit(const CardDetailState(status: CardDetailStatus.failure));
    }
  }

  /// Silent auto-save; errors propagate so the card can flag the failed cell.
  /// The reactive stream refreshes [CardDetailState.installments].
  Future<void> autoSave(List<PaymentInstallment> changed) =>
      _cards.saveInstallments(changed);

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
