import 'package:equatable/equatable.dart';

enum CardStatus {
  active('Activa'),
  debtor('Deudor'),
  paid('Pagada'),
  renewal('Renovación'),
  archived('Archivada');

  const CardStatus(this.label);

  final String label;

  /// Statuses of cards that may still hold a pending balance.
  bool get isOpen => this == active || this == debtor || this == renewal;
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
  ];
}

/// A card together with what the client still owes on it.
class CardBalance extends Equatable {
  const CardBalance(this.card, this.pending);

  final CreditCard card;
  final double pending;

  @override
  List<Object?> get props => [card, pending];
}
