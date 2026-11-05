import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/domain/repositories/client_repository.dart';
import '../../domain/services/payment_plan_calculator.dart';
import '../../domain/use_cases/credit_card_creation.dart';

enum CardCreationStatus { loading, ready, saving, success, failure }

class CardCreationState extends Equatable {
  const CardCreationState({
    this.status = CardCreationStatus.loading,
    this.clients = const [],
    this.client,
    this.amount,
    this.option,
    this.plan,
    this.colorHex = defaultColorHex,
    this.renewalBlocked = false,
    this.errorMessage,
    this.createdCardId,
  });

  static const defaultColorHex = '#800020';

  final CardCreationStatus status;
  final List<Client> clients;
  final Client? client;
  final double? amount;
  final PlanOption? option;
  final PaymentPlan? plan;
  final String colorHex;
  final bool renewalBlocked;
  final String? errorMessage;
  final String? createdCardId;

  List<PlanOption> get options =>
      amount == null ? const [] : PaymentPlanCalculator.optionsFor(amount!);

  bool get canSubmit =>
      client != null &&
      plan != null &&
      !renewalBlocked &&
      status != CardCreationStatus.saving;

  CardCreationState copyWith({
    CardCreationStatus? status,
    List<Client>? clients,
    Client? client,
    double? Function()? amount,
    PlanOption? Function()? option,
    PaymentPlan? Function()? plan,
    String? colorHex,
    bool? renewalBlocked,
    String? Function()? errorMessage,
    String? createdCardId,
  }) {
    return CardCreationState(
      status: status ?? this.status,
      clients: clients ?? this.clients,
      client: client ?? this.client,
      amount: amount != null ? amount() : this.amount,
      option: option != null ? option() : this.option,
      plan: plan != null ? plan() : this.plan,
      colorHex: colorHex ?? this.colorHex,
      renewalBlocked: renewalBlocked ?? this.renewalBlocked,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      createdCardId: createdCardId ?? this.createdCardId,
    );
  }

  @override
  List<Object?> get props => [
    status,
    clients,
    client,
    amount,
    option,
    plan,
    colorHex,
    renewalBlocked,
    errorMessage,
    createdCardId,
  ];
}

@injectable
class CardCreationCubit extends Cubit<CardCreationState> {
  CardCreationCubit(this._clients, this._creation)
    : super(const CardCreationState());

  final ClientRepository _clients;
  final CreditCardCreation _creation;

  static const lockMessage =
      'El cliente debe liquidar su tarjeta anterior antes de renovar';

  Future<void> start({Client? preselected}) async {
    try {
      final clients = preselected != null
          ? [preselected]
          : await _clients.watchClients().first;
      emit(state.copyWith(status: CardCreationStatus.ready, clients: clients));
      if (preselected != null) await selectClient(preselected);
    } on Object {
      emit(
        state.copyWith(
          status: CardCreationStatus.failure,
          errorMessage: () => 'No se pudo cargar la lista de clientes.',
        ),
      );
    }
  }

  Future<void> selectClient(Client client) async {
    emit(
      state.copyWith(
        client: client,
        errorMessage: () => null,
        status: CardCreationStatus.ready,
      ),
    );
    try {
      final blocked = await _creation.isRenewalBlocked(client.id);
      if (state.client?.id != client.id) return;
      emit(
        state.copyWith(
          renewalBlocked: blocked,
          errorMessage: () => blocked ? lockMessage : null,
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          errorMessage: () => 'No se pudo verificar las tarjetas del cliente.',
        ),
      );
    }
  }

  void selectAmount(double? amount) {
    final options = amount == null
        ? const <PlanOption>[]
        : PaymentPlanCalculator.optionsFor(amount);
    final option = options.isEmpty ? null : options.first;
    emit(
      state.copyWith(
        amount: () => amount,
        option: () => option,
        plan: () => _preview(amount, option),
      ),
    );
  }

  void selectOption(PlanOption option) {
    emit(
      state.copyWith(
        option: () => option,
        plan: () => _preview(state.amount, option),
      ),
    );
  }

  void selectColor(String colorHex) => emit(state.copyWith(colorHex: colorHex));

  Future<void> submit() async {
    final client = state.client;
    final amount = state.amount;
    if (!state.canSubmit || client == null || amount == null) return;

    emit(
      state.copyWith(
        status: CardCreationStatus.saving,
        errorMessage: () => null,
      ),
    );
    try {
      final id = await _creation(
        clientId: client.id,
        requestedAmount: amount,
        colorHex: state.colorHex,
        option: state.option,
      );
      emit(
        state.copyWith(status: CardCreationStatus.success, createdCardId: id),
      );
    } on RenewalBlockedException catch (e) {
      emit(
        state.copyWith(
          status: CardCreationStatus.failure,
          renewalBlocked: true,
          errorMessage: () => e.message,
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          status: CardCreationStatus.failure,
          errorMessage: () => 'No se pudo crear la tarjeta. Intente de nuevo.',
        ),
      );
    }
  }

  PaymentPlan? _preview(double? amount, PlanOption? option) {
    if (amount == null || option == null) return null;
    return PaymentPlanCalculator.calculate(
      requestedAmount: amount,
      cardId: 'preview',
      option: option,
    );
  }
}
