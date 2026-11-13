import '../services/payment_plan_calculator.dart';

class CreditPlan {
  const CreditPlan({
    required this.id,
    required this.amount,
    required this.installments,
    required this.installmentAmount,
    required this.isActive,
  });

  final int? id;
  final double amount;
  final int installments;
  final double installmentAmount;
  final bool isActive;

  double get total => installments * installmentAmount;
  PlanOption get option => PlanOption(installments, installmentAmount);
}
