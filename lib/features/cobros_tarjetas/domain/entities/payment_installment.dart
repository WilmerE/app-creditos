import 'package:equatable/equatable.dart';

enum PaymentType {
  cash,
  deposit,
  transfer;

  String get label => switch (this) {
    PaymentType.cash => 'Efectivo',
    PaymentType.deposit => 'Depósito',
    PaymentType.transfer => 'Transferencia',
  };
}

class PaymentInstallment extends Equatable {
  const PaymentInstallment({
    required this.id,
    required this.cardId,
    required this.scheduledDate,
    required this.amountPaid,
    required this.balanceAfter,
    this.type = PaymentType.cash,
    this.receiptNumber,
    this.isRenewal = false,
  });

  final String id;
  final String cardId;
  final DateTime scheduledDate;
  final double amountPaid;
  final double balanceAfter;
  final PaymentType type;
  final String? receiptNumber;
  final bool isRenewal;

  @override
  List<Object?> get props => [
    id,
    cardId,
    scheduledDate,
    amountPaid,
    balanceAfter,
    type,
    receiptNumber,
    isRenewal,
  ];

  PaymentInstallment copyWith({
    DateTime? scheduledDate,
    double? amountPaid,
    double? balanceAfter,
    PaymentType? type,
    String? receiptNumber,
    bool clearReceiptNumber = false,
    bool? isRenewal,
  }) {
    return PaymentInstallment(
      id: id,
      cardId: cardId,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      amountPaid: amountPaid ?? this.amountPaid,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      type: type ?? this.type,
      receiptNumber: clearReceiptNumber
          ? null
          : receiptNumber ?? this.receiptNumber,
      isRenewal: isRenewal ?? this.isRenewal,
    );
  }
}
