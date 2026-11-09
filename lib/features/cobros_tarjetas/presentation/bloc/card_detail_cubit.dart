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
    this.today,
    this.lateFee = const LateFee(),
  });

  final CardDetailStatus status;
  final CreditCard? card;
  final Client? client;
  final List<PaymentInstallment> installments;
  final DateTime? today;
  final LateFee lateFee;

  double get totalPaid =>
      installments.fold(0, (sum, i) => sum + i.principalPaid);

  double get pendingBalance =>
      ((card?.totalToPay ?? 0) - totalPaid).clamp(0, double.infinity);

  double get totalDueToday => pendingBalance + lateFee.amount;

  CardDetailState copyWith({
    CardDetailStatus? status,
    CreditCard? card,
    Client? client,
    List<PaymentInstallment>? installments,
    DateTime? today,
    LateFee? lateFee,
  }) {
    return CardDetailState(
      status: status ?? this.status,
      card: card ?? this.card,
      client: client ?? this.client,
      installments: installments ?? this.installments,
      today: today ?? this.today,
      lateFee: lateFee ?? this.lateFee,
    );
  }

  @override
  List<Object?> get props => [
    status,
    card,
    client,
    installments,
    today,
    lateFee,
  ];
}

@injectable
class CardDetailCubit extends Cubit<CardDetailState> {
  CardDetailCubit(this._cards, this._clients)
    : _clock = DateTime.now,
      super(const CardDetailState());

  CardDetailCubit.withClock(this._cards, this._clients, this._clock)
    : super(const CardDetailState());

  final CreditCardRepository _cards;
  final ClientRepository _clients;
  final DateTime Function() _clock;
  StreamSubscription<List<PaymentInstallment>>? _subscription;
  StreamSubscription<LateFee>? _moraSubscription;
  Timer? _midnight;

  Future<void> load(String cardId) async {
    emit(CardDetailState(today: _clock()));
    _scheduleMidnight();
    try {
      final card = await _cards.getCard(cardId);
      if (card == null) {
        emit(const CardDetailState(status: CardDetailStatus.notFound));
        return;
      }
      final client = await _clients.getById(card.clientId);
      if (client == null) {
        emit(const CardDetailState(status: CardDetailStatus.notFound));
        return;
      }
      await _cards.accrueMora(cardId, now: _clock());
      final installments = await _cards.watchInstallments(cardId).first;
      final fee = await _cards.watchMora(cardId).first;
      emit(
        CardDetailState(
          status: CardDetailStatus.ready,
          card: card,
          client: client,
          installments: installments,
          lateFee: fee,
          today: _clock(),
        ),
      );
      await _moraSubscription?.cancel();
      _moraSubscription = _cards
          .watchMora(cardId)
          .listen(
            (fee) => emit(state.copyWith(lateFee: fee)),
            onError: (Object _) =>
                emit(state.copyWith(status: CardDetailStatus.failure)),
          );
      await _subscription?.cancel();
      _subscription = _cards
          .watchInstallments(cardId)
          .listen(
            (installments) => emit(
              state.copyWith(installments: installments, today: _clock()),
            ),
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

  Future<void> addEmptyInstallment() {
    final card = state.card;
    if (card == null) throw StateError('La tarjeta no está disponible.');
    return _cards.addEmptyInstallment(card.id);
  }

  Future<void> deleteEmptyLastInstallment(String installmentId) {
    final card = state.card;
    if (card == null) throw StateError('La tarjeta no está disponible.');
    return _cards.deleteEmptyLastInstallment(card.id, installmentId);
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = _clock().toLocal();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () async {
      try {
        final card = state.card;
        if (card != null) await _cards.accrueMora(card.id, now: _clock());
        if (!isClosed) emit(state.copyWith(today: _clock()));
      } on Object {
        if (!isClosed) emit(state.copyWith(status: CardDetailStatus.failure));
      }
      if (isClosed) return;
      _scheduleMidnight();
    });
  }

  @override
  Future<void> close() {
    _midnight?.cancel();
    _subscription?.cancel();
    _moraSubscription?.cancel();
    return super.close();
  }
}
