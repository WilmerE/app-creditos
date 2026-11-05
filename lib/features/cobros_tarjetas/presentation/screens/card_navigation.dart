import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../injection_container.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../domain/entities/credit_card.dart';
import '../../domain/repositories/credit_card_repository.dart';
import 'card_creation_screen.dart';
import 'card_detail_screen.dart';

/// Opens the digital card of [client]: directly when it has a single card,
/// otherwise through a chooser (newest first).
Future<void> openClientCards(BuildContext context, Client client) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final cards = await getIt<CreditCardRepository>().cardsForClient(client.id);
  if (!context.mounted) return;

  if (cards.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text('${client.fullName} aún no tiene tarjetas.')),
    );
    return;
  }

  final CreditCard? selected = cards.length == 1
      ? cards.single
      : await showModalBottomSheet<CreditCard>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final card in cards)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorFromHex(card.colorHex),
                    ),
                    title: Text(
                      '${CurrencyFormatter.formatGtq(card.requestedAmount)} · ${card.status.label}',
                    ),
                    subtitle: Text(
                      'Inicio ${DateFormat('dd/MM/yyyy').format(card.startDate)}',
                    ),
                    onTap: () => Navigator.pop(sheetContext, card),
                  ),
              ],
            ),
          ),
        );
  if (selected == null) return;

  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => CardDetailScreen(cardId: selected.id),
    ),
  );
}

/// Opens the creation screen and, on success, the new card.
Future<void> createCardFor(BuildContext context, Client client) =>
    openCardCreation(context, client: client);

/// Without [client] the screen lets the user pick an existing client or
/// register a new one.
Future<void> openCardCreation(BuildContext context, {Client? client}) async {
  final navigator = Navigator.of(context);
  final cardId = await navigator.push<String>(
    MaterialPageRoute<String>(
      builder: (_) => CardCreationScreen(client: client),
    ),
  );
  if (cardId == null) return;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => CardDetailScreen(cardId: cardId)),
  );
}
