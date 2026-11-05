import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/contact_launcher.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/client.dart';
import '../bloc/client_bloc.dart';
import '../widgets/client_avatar.dart';
import 'client_form_screen.dart';

enum _ClientAction { edit, createCard, call, whatsApp }

class ClientListScreen extends StatelessWidget {
  const ClientListScreen({super.key, this.onCreateCard});

  /// Hook for the cobros_tarjetas feature; defaults to an informative message.
  final void Function(Client client)? onCreateCard;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<ClientBloc>()..add(const ClientsSubscriptionRequested()),
      child: _ClientListView(onCreateCard: onCreateCard),
    );
  }
}

class _ClientListView extends StatefulWidget {
  const _ClientListView({this.onCreateCard});

  final void Function(Client client)? onCreateCard;

  @override
  State<_ClientListView> createState() => _ClientListViewState();
}

class _ClientListViewState extends State<_ClientListView> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) context.read<ClientBloc>().add(ClientSearchChanged(text));
    });
  }

  void _openForm(BuildContext context, [Client? client]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: context.read<ClientBloc>(),
          child: ClientFormScreen(client: client),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onAction(
    BuildContext context,
    _ClientAction action,
    Client client,
  ) async {
    switch (action) {
      case _ClientAction.edit:
        _openForm(context, client);
      case _ClientAction.createCard:
        final callback = widget.onCreateCard;
        if (callback != null) {
          callback(client);
        } else {
          _snack(
            context,
            'Crear tarjeta para ${client.fullName}: próximamente.',
          );
        }
      case _ClientAction.call:
      case _ClientAction.whatsApp:
        final phone = client.primaryPhone;
        if (phone == null) {
          _snack(context, 'El cliente no tiene teléfono.');
          return;
        }
        final ok = action == _ClientAction.call
            ? await ContactLauncher.call(phone)
            : await ContactLauncher.whatsApp(phone);
        if (!ok && context.mounted) {
          _snack(context, 'No se pudo abrir la aplicación.');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          onPressed: () => _openForm(context),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Nuevo cliente'),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  onChanged: _onSearch,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por nombre, DPI o alias',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: BlocConsumer<ClientBloc, ClientState>(
                  listenWhen: (p, c) =>
                      c.message != null && p.message != c.message,
                  listener: (context, state) {
                    _snack(context, state.message!);
                    context.read<ClientBloc>().add(
                      const ClientMessageCleared(),
                    );
                  },
                  builder: (context, state) {
                    if (state.listStatus == ClientListStatus.loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state.clients.isEmpty) {
                      return Center(
                        child: Text(
                          state.query.isEmpty
                              ? 'Aún no hay clientes registrados.'
                              : 'Sin resultados para "${state.query}".',
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                      itemCount: state.clients.length,
                      itemBuilder: (context, index) {
                        final client = state.clients[index];
                        return _ClientCard(
                          client: client,
                          onTap: () => _openForm(context, client),
                          onAction: (a) => _onAction(context, a, client),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.client,
    required this.onTap,
    required this.onAction,
  });

  final Client client;
  final VoidCallback onTap;
  final ValueChanged<_ClientAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alias = client.alias;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClientAvatar(name: client.fullName, photoPath: client.photoPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.fullName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (alias != null && alias.isNotEmpty)
                      Text(alias, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      client.primaryPhone ?? 'Sin teléfono',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      client.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.credit_card, size: 16),
                      label: Text(
                        '${client.activeCardsCount} tarjetas activas',
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_ClientAction>(
                tooltip: 'Acciones',
                onSelected: onAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _ClientAction.edit,
                    child: Text('Editar'),
                  ),
                  PopupMenuItem(
                    value: _ClientAction.createCard,
                    child: Text('Crear tarjeta digital'),
                  ),
                  PopupMenuItem(
                    value: _ClientAction.call,
                    child: Text('Llamar'),
                  ),
                  PopupMenuItem(
                    value: _ClientAction.whatsApp,
                    child: Text('Enviar WhatsApp'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
