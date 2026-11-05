import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/credit_card.dart';
import '../bloc/card_detail_cubit.dart';
import '../widgets/tarjeta_digital_widget.dart';
import 'card_creation_screen.dart' show colorFromHex;

class CardDetailScreen extends StatelessWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CardDetailCubit>()..load(cardId),
      child: const CardDetailView(),
    );
  }
}

class CardDetailView extends StatelessWidget {
  const CardDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CardDetailCubit, CardDetailState>(
      builder: (context, state) {
        final card = state.card;
        final client = state.client;
        return Scaffold(
          appBar: AppBar(
            title: Text(client?.fullName ?? 'Tarjeta'),
            actions: [
              if (card != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      'Pendiente ${CurrencyFormatter.formatGtq(state.pendingBalance)}',
                    ),
                  ),
                ),
            ],
          ),
          body: switch (state.status) {
            CardDetailStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            CardDetailStatus.notFound => const Center(
              child: Text('No se encontró la tarjeta.'),
            ),
            CardDetailStatus.failure => const Center(
              child: Text('No se pudo cargar la tarjeta.'),
            ),
            CardDetailStatus.ready => SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: TarjetaDigitalWidget(
                customer: TarjetaCustomerInfo(
                  name: client!.fullName,
                  address: client.address,
                  phone: client.phones.join(' / '),
                  dpi: client.dpi ?? '',
                  reference: client.alias ?? '',
                  startDate: card!.startDate,
                  requestedAmount: card.requestedAmount,
                  paymentPlan: _planLabel(card),
                  photo: _photoOf(client.photoPath),
                ),
                initialBalance: card.totalToPay,
                payments: state.installments,
                renewalColor: colorFromHex(card.colorHex)
                    .withValues(alpha: 0.18),
                onAutoSave: context.read<CardDetailCubit>().autoSave,
              ),
            ),
          },
        );
      },
    );
  }

  String _planLabel(CreditCard card) =>
      '${card.totalInstallments} x ${CurrencyFormatter.formatGtq(card.weeklyAmount)}';

  ImageProvider<Object>? _photoOf(String? path) {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? FileImage(file) : null;
  }
}
