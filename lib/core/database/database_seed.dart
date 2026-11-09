import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/cobros_tarjetas/domain/entities/credit_card.dart';
import '../../features/cobros_tarjetas/domain/entities/payment_installment.dart';
import '../../features/cobros_tarjetas/domain/services/payment_plan_calculator.dart';
import 'app_database.dart';

enum DatabaseSeedResult { inserted, alreadyInserted }

class DatabaseSeed {
  const DatabaseSeed(this._database);

  final AppDatabase _database;
  static const _marker = 'database_seed_guatemala_v1';
  static const _uuid = Uuid();

  static const _firstNames = [
    'María',
    'José',
    'Ana',
    'Carlos',
    'Rosa',
    'Juan',
    'Marta',
    'Luis',
    'Carmen',
    'Pedro',
    'Gloria',
    'Miguel',
    'Sandra',
    'Francisco',
    'Elena',
    'Óscar',
    'Patricia',
    'Manuel',
    'Silvia',
    'Jorge',
  ];
  static const _lastNames = [
    'López',
    'García',
    'Hernández',
    'Pérez',
    'Morales',
    'Ramírez',
    'Castillo',
    'González',
    'Méndez',
    'Cruz',
    'Aguilar',
    'Rodríguez',
  ];
  static const _places = [
    'Zona 1, Zacapa, Zacapa',
    'Barrio El Centro, Gualán, Zacapa',
    'Colonia Las Flores, Chiquimula, Chiquimula',
    'Barrio El Calvario, Esquipulas, Chiquimula',
    'Zona 6, Ciudad de Guatemala, Guatemala',
    'Zona 2, Mixco, Guatemala',
  ];
  static const _aliases = [
    'La tienda',
    'Don del mercado',
    'Doña del comedor',
    'La panadería',
    'El taller',
    'La abarrotería',
    'El puesto',
    'La costurera',
  ];
  static const _amounts = [500.0, 1000.0, 1500.0, 2000.0, 3000.0, 5000.0];
  static const _colors = ['#800020', '#1565C0', '#2E7D32', '#EF6C00'];

  /// Seeds an empty business database once. All records and the marker commit
  /// together; any failure leaves the database unchanged.
  Future<DatabaseSeedResult> run({DateTime? now}) {
    final date = now ?? DateTime.now();
    final today = DateTime(date.year, date.month, date.day);
    return _database.transaction(() async {
      final marker = await (_database.select(
        _database.syncMetadata,
      )..where((row) => row.key.equals(_marker))).getSingleOrNull();
      if (marker != null) return DatabaseSeedResult.alreadyInserted;

      final existing = await _database
          .customSelect(
            'SELECT EXISTS(SELECT 1 FROM clients) OR '
            'EXISTS(SELECT 1 FROM client_phones) OR '
            'EXISTS(SELECT 1 FROM cards) OR EXISTS(SELECT 1 FROM payments) AS occupied',
          )
          .getSingle();
      if (existing.read<int>('occupied') != 0) {
        throw StateError(
          'Los datos de prueba solo pueden cargarse en una base sin clientes, tarjetas ni pagos.',
        );
      }

      final clients = <ClientsTableCompanion>[];
      final phones = <ClientPhonesCompanion>[];
      final cards = <CardsTableCompanion>[];
      final payments = <PaymentsCompanion>[];
      final mora = <MoraCompanion>[];
      final tracking = <MoraTrackingCompanion>[];

      for (var clientIndex = 0; clientIndex < 80; clientIndex++) {
        final clientId = _uuid.v4();
        final count = clientIndex < 20
            ? 1
            : clientIndex < 60
            ? 2
            : 5;
        final latestStatus = clientIndex < 20
            ? [
                CardStatus.active,
                CardStatus.debtor,
                CardStatus.paid,
              ][clientIndex % 3]
            : [
                CardStatus.active,
                CardStatus.debtor,
                CardStatus.paid,
                CardStatus.renewal,
              ][(clientIndex - 20) % 4];
        final latestDaysAgo = switch (latestStatus) {
          CardStatus.active => 19,
          CardStatus.renewal => 160,
          CardStatus.debtor => 90,
          CardStatus.paid => 210,
          CardStatus.deactivated => 90,
          CardStatus.archived => throw StateError(
            'Estado de prueba no válido.',
          ),
        };
        final earliestStart = _daysBefore(
          today,
          latestDaysAgo + 210 * (count - 1),
        );
        final createdAt = _daysBefore(earliestStart, 10);
        final firstName = _firstNames[clientIndex % _firstNames.length];
        final lastName = _lastNames[(clientIndex ~/ 2) % _lastNames.length];
        final secondLastName =
            _lastNames[(clientIndex + 5) % _lastNames.length];
        clients.add(
          ClientsTableCompanion.insert(
            id: clientId,
            fullName: '$firstName $lastName $secondLastName',
            address:
                '${1 + clientIndex % 20} avenida ${1 + clientIndex % 15}-${10 + clientIndex % 80}, ${_places[clientIndex % _places.length]}',
            alias: Value(
              '${_aliases[clientIndex % _aliases.length]} de $firstName',
            ),
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
        phones.add(
          ClientPhonesCompanion.insert(
            clientId: clientId,
            phoneNumber:
                '5${(1000000 + clientIndex).toString().padLeft(7, '0')}',
          ),
        );

        for (var cardIndex = 0; cardIndex < count; cardIndex++) {
          final isLatest = cardIndex == count - 1;
          final status = isLatest ? latestStatus : CardStatus.paid;
          final isRenewal = cardIndex > 0;
          final cardId = _uuid.v4();
          final start = _daysBefore(
            today,
            latestDaysAgo + 210 * (count - 1 - cardIndex),
          );
          final amount = _amounts[(clientIndex + cardIndex) % _amounts.length];
          final options = PaymentPlanCalculator.optionsFor(amount);
          final option =
              options[(clientIndex ~/ 6 + cardIndex) % options.length];
          final plan = PaymentPlanCalculator.calculate(
            requestedAmount: amount,
            cardId: cardId,
            startDate: start,
            option: option,
            isRenewal: isRenewal,
          );
          cards.add(
            CardsTableCompanion.insert(
              id: cardId,
              clientId: clientId,
              requestedAmount: amount,
              deliveredAmount: amount,
              totalInstallments: option.installments,
              weeklyAmount: option.installmentAmount,
              status: Value(status.name),
              colorHex: Value(
                _colors[(clientIndex + cardIndex) % _colors.length],
              ),
              startDate: start,
              createdAt: start,
            ),
          );
          if (status == CardStatus.debtor) {
            mora.addAll([
              MoraCompanion.insert(
                cardId: cardId,
                createdAt: _daysBefore(today, 1),
              ),
              MoraCompanion.insert(cardId: cardId, createdAt: today),
            ]);
          }
          tracking.add(
            MoraTrackingCompanion.insert(cardId: cardId, lastCheckedAt: today),
          );

          var balance = plan.total;
          for (var i = 0; i < plan.installments.length; i++) {
            final item = plan.installments[i];
            final paid =
                status == CardStatus.paid || status == CardStatus.renewal
                ? option.installmentAmount
                : i < (status == CardStatus.debtor ? 1 : 2)
                ? option.installmentAmount
                : i == (status == CardStatus.debtor ? 1 : 2)
                ? option.installmentAmount / 2
                : 0.0;
            balance -= paid;
            final type = paid == 0
                ? PaymentType.cash
                : PaymentType.values[(clientIndex + cardIndex + i) %
                      PaymentType.values.length];
            payments.add(
              PaymentsCompanion.insert(
                id: item.id,
                cardId: Value(cardId),
                scheduledDate: Value(item.scheduledDate),
                amountPaid: Value(paid),
                balanceAfter: balance,
                paymentType: Value(type.name),
                receiptNumber: Value(
                  type == PaymentType.cash ? null : 'SEED-$cardId-$i',
                ),
                isRenewal: Value(isRenewal),
                updatedAt: Value(paid > 0 ? item.scheduledDate! : start),
                createdAt: Value(paid > 0 ? item.scheduledDate : null),
                createdAtEstimated: Value(paid > 0),
              ),
            );
          }
        }
      }

      await _database.batch((batch) {
        batch.insertAll(_database.clientsTable, clients);
        batch.insertAll(_database.clientPhones, phones);
        batch.insertAll(_database.cardsTable, cards);
        batch.insertAll(_database.payments, payments);
        batch.insertAll(_database.mora, mora);
        batch.insertAll(_database.moraTracking, tracking);
        batch.insert(
          _database.syncMetadata,
          SyncMetadataCompanion.insert(key: _marker),
        );
      });
      return DatabaseSeedResult.inserted;
    });
  }

  static DateTime _daysBefore(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day - days);
}
