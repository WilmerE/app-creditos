import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../injection_container.dart';
import '../../../../core/database/app_database.dart';
import '../../../enterprise/data/enterprise_config_repository.dart';
import '../../../enterprise/domain/enterprise_config.dart';
import '../../domain/entities/credit_card.dart';
import '../bloc/card_detail_cubit.dart';
import '../services/card_snapshot_service.dart';
import '../widgets/tarjeta_digital_widget.dart';
import 'card_creation_screen.dart' show colorFromHex;

class CardDetailScreen extends StatelessWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CardDetailCubit>()..load(cardId),
      child: StreamBuilder<EnterpriseConfig>(
        stream: EnterpriseConfigRepository(getIt<AppDatabase>()).watch(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Scaffold(
              body: Center(
                child: Text('No se pudo cargar la configuración empresarial.'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return CardDetailView(enterpriseConfig: snapshot.data!);
        },
      ),
    );
  }
}

class CardDetailView extends StatefulWidget {
  const CardDetailView({
    super.key,
    this.enterpriseConfig = const EnterpriseConfig(),
  });

  final EnterpriseConfig enterpriseConfig;

  @override
  State<CardDetailView> createState() => _CardDetailViewState();
}

class _CardDetailViewState extends State<CardDetailView> {
  final GlobalKey _snapshotKey = GlobalKey();
  final CardSnapshotService _snapshotService = const CardSnapshotService();
  bool _exportMode = false;

  Future<File?> _capture() async {
    setState(() => _exportMode = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      return await _snapshotService.capture(_snapshotKey);
    } finally {
      if (mounted) setState(() => _exportMode = false);
    }
  }

  Future<void> _share(String? phone, String customerName) async {
    try {
      final file = await _capture();
      if (file == null || !mounted) return;
      
      // Compartir directamente el archivo generado
      await _snapshotService.share(file, text: 'Estado de cuenta de $customerName');
      
      if (phone == null || phone.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay teléfono registrado para este cliente.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo compartir la tarjeta.')),
        );
      }
    }
  }

  Future<void> _save() async {
    try {
      final file = await _capture();
      if (file == null || !mounted) return;
      final saved = await _snapshotService.save(file);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imagen guardada en ${saved.path}')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar la imagen: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enterpriseConfig = widget.enterpriseConfig;
    return BlocBuilder<CardDetailCubit, CardDetailState>(
      builder: (context, state) {
        final card = state.card;
        final client = state.client;
        return Scaffold(
          appBar: AppBar(
            title: Text(client?.fullName ?? 'Tarjeta'),
            actions: [
              if (card != null)
                PopupMenuButton<String>(
                  tooltip: 'Exportar tarjeta',
                  onSelected: (value) => value == 'share'
                      ? _share(client?.primaryPhone, client?.fullName ?? 'cliente')
                      : _save(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Compartir por WhatsApp'))),
                    PopupMenuItem(value: 'save', child: ListTile(leading: Icon(Icons.download), title: Text('Guardar imagen'))),
                  ],
                ),
              if (card != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      'Total hoy ${CurrencyFormatter.formatGtq(state.totalDueToday)}',
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
              child: RepaintBoundary(
                key: _snapshotKey,
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
                weeklyAmount: card.weeklyAmount,
                enterpriseConfig: enterpriseConfig,
                payments: state.installments,
                capitalPending: state.pendingBalance,
                lateFee: state.lateFee,
                renewalColor: colorFromHex(card.colorHex)
                    .withValues(alpha: 0.18),
                onAutoSave: context.read<CardDetailCubit>().autoSave,
                onAddRow: context.read<CardDetailCubit>().addEmptyInstallment,
                onDeleteRow: context
                    .read<CardDetailCubit>()
                    .deleteEmptyLastInstallment,
                readOnly: _exportMode,
                ),
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
