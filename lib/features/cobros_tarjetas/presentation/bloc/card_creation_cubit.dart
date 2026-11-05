import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/domain/repositories/client_repository.dart';
import '../../domain/services/payment_plan_calculator.dart';
import '../../domain/use_cases/create_card_with_new_client.dart';
import '../../domain/use_cases/credit_card_creation.dart';

enum CardCreationStatus { loading, ready, saving, success, failure }

enum ClientMode { existing, newClient }

enum ClientCardFilter { all, eligible, withActiveCard }

/// Data typed in the quick registration form of a new client.
class NewClientDraft extends Equatable {
  const NewClientDraft({
    this.name = '',
    this.address = '',
    this.phone = '',
    this.dpi = '',
    this.alias = '',
    this.photoPath,
  });

  final String name;
  final String address;
  final String phone;
  final String dpi;
  final String alias;
  final String? photoPath;

  bool get phoneValid =>
      phone.trim().isEmpty || _phoneRegex.hasMatch(phone.trim());

  bool get isValid =>
      name.trim().isNotEmpty && address.trim().isNotEmpty && phoneValid;

  static final _phoneRegex = RegExp(r'^[0-9+\-\s()]{7,20}$');

  NewClientDraft copyWith({
    String? name,
    String? address,
    String? phone,
    String? dpi,
    String? alias,
    String? Function()? photoPath,
  }) {
    return NewClientDraft(
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      dpi: dpi ?? this.dpi,
      alias: alias ?? this.alias,
      photoPath: photoPath != null ? photoPath() : this.photoPath,
    );
  }

  @override
  List<Object?> get props => [name, address, phone, dpi, alias, photoPath];
}

class CardCreationState extends Equatable {
  const CardCreationState({
    this.status = CardCreationStatus.loading,
    this.clients = const [],
    this.blockedClientIds = const {},
    this.mode = ClientMode.existing,
    this.query = '',
    this.filter = ClientCardFilter.all,
    this.draft = const NewClientDraft(),
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
  final Set<String> blockedClientIds;
  final ClientMode mode;
  final String query;
  final ClientCardFilter filter;
  final NewClientDraft draft;
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

  bool hasActiveCard(Client client) => blockedClientIds.contains(client.id);

  /// Clients matching the search text and the card-status filter.
  List<Client> get visibleClients {
    final term = query.trim().toLowerCase();
    return clients
        .where((c) {
          switch (filter) {
            case ClientCardFilter.all:
              break;
            case ClientCardFilter.eligible:
              if (hasActiveCard(c)) return false;
            case ClientCardFilter.withActiveCard:
              if (!hasActiveCard(c)) return false;
          }
          if (term.isEmpty) return true;
          return c.fullName.toLowerCase().contains(term) ||
              (c.alias ?? '').toLowerCase().contains(term) ||
              (c.dpi ?? '').contains(term);
        })
        .toList(growable: false);
  }

  bool get hasValidClient => mode == ClientMode.newClient
      ? draft.isValid
      : client != null && !renewalBlocked;

  bool get canSubmit =>
      hasValidClient && plan != null && status != CardCreationStatus.saving;

  CardCreationState copyWith({
    CardCreationStatus? status,
    List<Client>? clients,
    Set<String>? blockedClientIds,
    ClientMode? mode,
    String? query,
    ClientCardFilter? filter,
    NewClientDraft? draft,
    Client? client,
    bool clearClient = false,
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
      blockedClientIds: blockedClientIds ?? this.blockedClientIds,
      mode: mode ?? this.mode,
      query: query ?? this.query,
      filter: filter ?? this.filter,
      draft: draft ?? this.draft,
      client: clearClient ? null : client ?? this.client,
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
    blockedClientIds,
    mode,
    query,
    filter,
    draft,
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
  CardCreationCubit(this._clients, this._creation, this._creationWithClient)
    : super(const CardCreationState());

  final ClientRepository _clients;
  final CreditCardCreation _creation;
  final CreateCardWithNewClient _creationWithClient;

  static const lockMessage =
      'El cliente debe liquidar su tarjeta anterior antes de renovar';

  Future<void> start({Client? preselected}) async {
    try {
      final clients = preselected != null
          ? [preselected]
          : await _clients.watchClients().first;
      final blocked = await _creation.blockedClientIds();
      emit(
        state.copyWith(
          status: CardCreationStatus.ready,
          clients: clients,
          blockedClientIds: blocked,
        ),
      );
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

  void setMode(ClientMode mode) {
    if (mode == state.mode) return;
    emit(
      state.copyWith(
        mode: mode,
        clearClient: mode == ClientMode.newClient,
        renewalBlocked: false,
        errorMessage: () => null,
        status: CardCreationStatus.ready,
      ),
    );
  }

  void setQuery(String query) => emit(state.copyWith(query: query));

  void setFilter(ClientCardFilter filter) =>
      emit(state.copyWith(filter: filter));

  void updateDraft(NewClientDraft draft) => emit(state.copyWith(draft: draft));

  Future<void> selectClient(Client client) async {
    emit(
      state.copyWith(
        client: client,
        renewalBlocked: state.hasActiveCard(client),
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
    final amount = state.amount;
    if (!state.canSubmit || amount == null) return;

    emit(
      state.copyWith(
        status: CardCreationStatus.saving,
        errorMessage: () => null,
      ),
    );
    try {
      final String id;
      if (state.mode == ClientMode.newClient) {
        final draft = state.draft;
        final now = DateTime.now();
        id = await _creationWithClient(
          client: Client(
            id: const Uuid().v4(),
            fullName: draft.name.trim(),
            address: draft.address.trim(),
            phones: draft.phone.trim().isEmpty
                ? const []
                : [draft.phone.trim()],
            dpi: draft.dpi.trim().isEmpty ? null : draft.dpi.trim(),
            alias: draft.alias.trim().isEmpty ? null : draft.alias.trim(),
            createdAt: now,
            updatedAt: now,
          ),
          photoSourcePath: draft.photoPath,
          requestedAmount: amount,
          colorHex: state.colorHex,
          option: state.option,
        );
      } else {
        id = await _creation(
          clientId: state.client!.id,
          requestedAmount: amount,
          colorHex: state.colorHex,
          option: state.option,
        );
      }
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
