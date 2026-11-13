import 'package:injectable/injectable.dart';

import '../../../../core/database/transaction_runner.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/domain/repositories/client_repository.dart';
import '../services/payment_plan_calculator.dart';
import 'credit_card_creation.dart';

/// Registers a new client and issues its first card atomically: if the card
/// cannot be created the client row is rolled back too.
@injectable
class CreateCardWithNewClient {
  const CreateCardWithNewClient(this._clients, this._creation, this._tx);

  final ClientRepository _clients;
  final CreditCardCreation _creation;
  final TransactionRunner _tx;

  /// Returns the id of the created card.
  Future<String> call({
    required Client client,
    String? photoSourcePath,
    required double requestedAmount,
    required String colorHex,
    PlanOption? option,
    List<PlanOption>? availableOptions,
    DateTime? startDate,
    DateTime? firstPaymentDate,
    int? folderId,
  }) {
    return _tx.run(() async {
      await _clients.save(client, newPhotoSourcePath: photoSourcePath);
      return _creation(
        clientId: client.id,
        requestedAmount: requestedAmount,
        colorHex: colorHex,
        option: option,
        availableOptions: availableOptions,
        startDate: startDate,
        firstPaymentDate: firstPaymentDate,
        folderId: folderId,
      );
    });
  }
}
