import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cobros_tarjetas/domain/entities/credit_card.dart';
import '../../domain/dashboard_repository.dart';

enum DashboardStatus { loading, ready, error }

enum DashboardFilter {
  active,
  debtor,
  renewal,
  paid,
  deactivated,
  todayDue,
  cash,
}

class DashboardState {
  const DashboardState({
    this.status = DashboardStatus.loading,
    this.cards = const [],
    this.filter = DashboardFilter.todayDue,
    required this.today,
  });

  final DashboardStatus status;
  final List<DashboardCard> cards;
  final DashboardFilter filter;
  final DateTime today;

  bool _isToday(DateTime? date) {
    if (date == null) return false;
    final local = date.toLocal();
    return local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
  }

  int count(CardStatus status) => cards.where((card) {
    return card.status == status &&
        (status != CardStatus.renewal || card.pendingBalance <= 0.005);
  }).length;

  double get projectedToday => cards
      .where((card) => card.status != CardStatus.deactivated)
      .fold(
        0,
        (total, card) =>
            total +
            card.payments
                    .where((p) => !p.isManual && _isToday(p.scheduledDate))
                    .length *
                card.weeklyAmount,
      );

  double get estimatedPaidToday => cards
      .where((card) => card.status != CardStatus.deactivated)
      .fold(
        0,
        (total, card) =>
            total +
            card.payments
                .where((p) => _isToday(p.updatedAt))
                .fold<double>(0, (sum, payment) => sum + payment.amountPaid),
      );

  List<TodayDuePayment> get todayDuePayments {
    final duePayments =
        [
          for (final card in cards)
            if (card.status == CardStatus.active ||
                card.status == CardStatus.debtor)
              for (final payment in card.payments)
                if (!payment.isManual && _isToday(payment.scheduledDate))
                  TodayDuePayment(card: card, payment: payment),
        ]..sort(
          (a, b) => a.card.clientName.toLowerCase().compareTo(
            b.card.clientName.toLowerCase(),
          ),
        );
    return duePayments;
  }

  int get pendingDueTodayCount =>
      todayDuePayments.where((due) => !due.isPaid).length;

  int get paidDueTodayCount =>
      todayDuePayments.where((due) => due.isPaid).length;

  List<DashboardCard> get visibleCards => cards
      .where((card) {
        return switch (filter) {
          DashboardFilter.active => card.status == CardStatus.active,
          DashboardFilter.debtor => card.status == CardStatus.debtor,
          DashboardFilter.renewal =>
            card.status == CardStatus.renewal && card.pendingBalance <= 0.005,
          DashboardFilter.paid => card.status == CardStatus.paid,
          DashboardFilter.deactivated => card.status == CardStatus.deactivated,
          DashboardFilter.todayDue => false,
          DashboardFilter.cash =>
            card.status != CardStatus.deactivated &&
                card.payments.any(
                  (p) =>
                      (!p.isManual && _isToday(p.scheduledDate)) ||
                      (p.amountPaid > 0 && _isToday(p.updatedAt)),
                ),
        };
      })
      .toList(growable: false);
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(DashboardState(today: (clock ?? DateTime.now)()));

  final DashboardRepository _repository;
  final DateTime Function() _clock;
  StreamSubscription<List<DashboardCard>>? _subscription;
  Timer? _midnight;

  void start() {
    _subscription?.cancel();
    emit(DashboardState(today: _clock(), filter: state.filter));
    _subscription = _repository.watchCards().listen(
      (cards) {
        emit(
          DashboardState(
            status: DashboardStatus.ready,
            cards: cards
                .where((card) => card.status != CardStatus.archived)
                .toList(growable: false),
            filter: state.filter,
            today: _clock(),
          ),
        );
      },
      onError: (Object error, StackTrace stack) {
        emit(
          DashboardState(
            status: DashboardStatus.error,
            filter: state.filter,
            today: _clock(),
          ),
        );
      },
    );
    _scheduleMidnight();
  }

  void selectFilter(DashboardFilter filter) {
    emit(
      DashboardState(
        status: state.status,
        cards: state.cards,
        filter: filter,
        today: _clock(),
      ),
    );
  }

  Future<void> changeStatus(String cardId, CardStatus status) =>
      _repository.changeStatus(cardId, status);

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = _clock();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () {
      start();
    });
  }

  @override
  Future<void> close() async {
    _midnight?.cancel();
    await _subscription?.cancel();
    await super.close();
  }
}
