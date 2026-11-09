import 'package:equatable/equatable.dart';

enum CardStatus {
  active('Activa'),
  debtor('Deudor'),
  paid('Pagada'),
  renewal('Renovación'),
  deactivated('Desactivada'),
  archived('Archivada');

  const CardStatus(this.label);

  final String label;

  /// Statuses of cards that may still hold a pending balance.
  bool get isOpen =>
      this == active ||
      this == debtor ||
      this == renewal ||
      this == deactivated;
}

extension CardStatusBalanceMapping on CardStatus {
  CardStatus forBalance({
    required double pendingBalance,
    required bool hasOverdueInstallment,
  }) {
    if (this == CardStatus.archived || this == CardStatus.deactivated) {
      return this;
    }

    if (pendingBalance <= 0.005) {
      return this == CardStatus.paid ? this : CardStatus.renewal;
    }

    if (this == CardStatus.active && hasOverdueInstallment) {
      return CardStatus.debtor;
    }

    if (this == CardStatus.renewal || this == CardStatus.paid) {
      return hasOverdueInstallment ? CardStatus.debtor : CardStatus.active;
    }

    return this;
  }
}

class CreditCard extends Equatable {
  const CreditCard({
    required this.id,
    required this.clientId,
    required this.requestedAmount,
    required this.deliveredAmount,
    required this.totalInstallments,
    required this.weeklyAmount,
    required this.status,
    required this.colorHex,
    required this.startDate,
    required this.createdAt,
    this.folderId,
  });

  final String id;
  final String clientId;
  final double requestedAmount;
  final double deliveredAmount;
  final int totalInstallments;
  final double weeklyAmount;
  final CardStatus status;
  final String colorHex;
  final DateTime startDate;
  final DateTime createdAt;
  final int? folderId;

  double get totalToPay => totalInstallments * weeklyAmount;

  @override
  List<Object?> get props => [
    id,
    clientId,
    requestedAmount,
    deliveredAmount,
    totalInstallments,
    weeklyAmount,
    status,
    colorHex,
    startDate,
    createdAt,
    folderId,
  ];
}

class LateFee extends Equatable {
  const LateFee({
    this.days = 0,
    this.dueDate,
    this.rate = 20,
    this.dates = const [],
  });

  final int days;
  final DateTime? dueDate;
  final int rate;
  final List<DateTime> dates;

  double get amount => days * rate.toDouble();

  @override
  List<Object?> get props => [days, dueDate, rate, dates];
}

/// A card together with what the client still owes on it.
class CardBalance extends Equatable {
  const CardBalance(this.card, this.pending);

  final CreditCard card;
  final double pending;

  @override
  List<Object?> get props => [card, pending];
}
