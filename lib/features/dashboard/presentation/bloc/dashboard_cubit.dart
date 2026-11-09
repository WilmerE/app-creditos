import 'dart:async';

import '../../../../core/database/app_database.dart';
import '../../data/operational_notifications_local_data_source.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cobros_tarjetas/domain/entities/credit_card.dart';
import '../../../capital_groups/domain/entities/capital_group.dart';
import '../../../capital_groups/domain/repositories/capital_group_repository.dart';
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
    this.capitalGroups = const [],
    this.selectedFolderId,
    required this.today,
  });

  final DashboardStatus status;
  final List<DashboardCard> cards;
  final DashboardFilter filter;
  final List<CapitalGroup> capitalGroups;
  final int? selectedFolderId;
  final DateTime today;

  DashboardState copyWith({
    DashboardStatus? status,
    List<DashboardCard>? cards,
    DashboardFilter? filter,
    List<CapitalGroup>? capitalGroups,
    int? selectedFolderId,
    bool clearSelectedFolder = false,
    DateTime? today,
  }) => DashboardState(
    status: status ?? this.status,
    cards: cards ?? this.cards,
    filter: filter ?? this.filter,
    capitalGroups: capitalGroups ?? this.capitalGroups,
    selectedFolderId: clearSelectedFolder
        ? null
        : selectedFolderId ?? this.selectedFolderId,
    today: today ?? this.today,
  );

  List<DashboardCard> get selectedCapitalCards => cards
      .where((card) => card.folderId == selectedFolderId)
      .toList(growable: false);

  bool _isToday(DateTime? date) {
    if (date == null) return false;
    final local = date.toLocal();
    return local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
  }

  int count(CardStatus status) => selectedCapitalCards.where((card) {
    return card.status == status &&
        (status != CardStatus.renewal || card.pendingBalance <= 0.005);
  }).length;

  double get projectedToday => selectedCapitalCards
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

  double get estimatedPaidToday => selectedCapitalCards
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
          for (final card in selectedCapitalCards)
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

  List<DashboardCard> get visibleCards => selectedCapitalCards
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
  DashboardCubit(
    this._repository, {
    DateTime Function()? clock,
    this.capitalGroupRepository,
    this.database,
  }) : _clock = clock ?? DateTime.now,
       super(DashboardState(today: (clock ?? DateTime.now)()));

  final DashboardRepository _repository;
  final DateTime Function() _clock;
  final CapitalGroupRepository? capitalGroupRepository;
  final AppDatabase? database;
  StreamSubscription<List<DashboardCard>>? _subscription;
  StreamSubscription<List<CapitalGroup>>? _capitalGroupsSubscription;
  Timer? _midnight;
  Timer? _cutoffTimer;

  void start() {
    _subscription?.cancel();
    _capitalGroupsSubscription?.cancel();
    emit(state.copyWith(status: DashboardStatus.loading, today: _clock()));
    if (database != null) {
      final alerts = OperationalNotificationsLocalDataSource(database!);
      alerts.evaluateCollectionCutoff(now: _clock());
      _cutoffTimer?.cancel();
      _cutoffTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        alerts.evaluateCollectionCutoff(now: _clock());
        emit(state.copyWith(today: _clock()));
      });
    }
    _capitalGroupsSubscription = capitalGroupRepository?.watchGroups().listen((
      groups,
    ) {
      final selectionStillExists = groups.any(
        (group) => group.id == state.selectedFolderId,
      );
      emit(
        state.copyWith(
          capitalGroups: groups,
          clearSelectedFolder:
              state.selectedFolderId != null && !selectionStillExists,
        ),
      );
    });
    _subscription = _repository.watchCards().listen(
      (cards) {
        emit(
          state.copyWith(
            status: DashboardStatus.ready,
            cards: cards
                .where((card) => card.status != CardStatus.archived)
                .toList(growable: false),
            today: _clock(),
          ),
        );
      },
      onError: (Object error, StackTrace stack) {
        emit(state.copyWith(status: DashboardStatus.error, today: _clock()));
      },
    );
    _scheduleMidnight();
  }

  void selectFilter(DashboardFilter filter) {
    emit(state.copyWith(filter: filter, today: _clock()));
  }

  void selectCapitalGroup(int? folderId) => emit(
    state.copyWith(
      selectedFolderId: folderId,
      clearSelectedFolder: folderId == null,
      today: _clock(),
    ),
  );

  Future<void> changeStatus(String cardId, CardStatus status) =>
      _repository.changeStatus(cardId, status);

  void _scheduleMidnight() {
    _midnight?.cancel();
    _cutoffTimer?.cancel();
    final now = _clock();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () {
      start();
    });
  }

  @override
  Future<void> close() async {
    _midnight?.cancel();
    await _capitalGroupsSubscription?.cancel();
    await _subscription?.cancel();
    await super.close();
  }
}
