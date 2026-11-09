import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../injection_container.dart';
import '../../domain/entities/capital_group.dart';
import '../../domain/use_cases/manage_capital_groups.dart';
import '../cubit/capital_group_cubit.dart';

class CapitalGroupsScreen extends StatelessWidget {
  const CapitalGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => CapitalGroupCubit(getIt<ManageCapitalGroups>())..start(),
    child: const _CapitalGroupsView(),
  );
}

class _CapitalGroupsView extends StatelessWidget {
  const _CapitalGroupsView();

  Future<void> _editGroup(BuildContext context, {CapitalGroup? group}) async {
    final values = await showDialog<({String name, String? description})>(
      context: context,
      builder: (_) => _CapitalGroupDialog(group: group),
    );
    if (values == null || !context.mounted) return;
    try {
      final cubit = context.read<CapitalGroupCubit>();
      if (group == null) {
        await cubit.create(name: values.name, description: values.description);
      } else {
        await cubit.update(
          id: group.id,
          name: values.name,
          description: values.description,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            group == null ? 'Carpeta creada.' : 'Carpeta actualizada.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la carpeta: $error')),
      );
    }
  }

  Future<void> _deleteGroup(BuildContext context, CapitalGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar carpeta'),
        content: Text(
          '¿Eliminar “${group.name}”? Las tarjetas asociadas pasarán a Capital Principal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<CapitalGroupCubit>().delete(group.id);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la carpeta: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Carpetas de capital')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _editGroup(context),
      icon: const Icon(Icons.create_new_folder_outlined),
      label: const Text('Nueva carpeta'),
    ),
    body: BlocBuilder<CapitalGroupCubit, CapitalGroupState>(
      builder: (context, state) {
        if (state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.error != null) {
          return Center(child: Text(state.error!));
        }
        if (state.groups.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aún no hay carpetas. Las tarjetas sin una carpeta pertenecen a Capital Principal.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            const ListTile(
              leading: Icon(Icons.account_balance_outlined),
              title: Text('Capital Principal'),
              subtitle: Text('Tarjetas sin carpeta asignada.'),
            ),
            for (final group in state.groups)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(group.name),
                  subtitle: group.description == null
                      ? null
                      : Text(group.description!),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Editar carpeta',
                        onPressed: () => _editGroup(context, group: group),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar carpeta',
                        onPressed: () => _deleteGroup(context, group),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _CapitalGroupDialog extends StatefulWidget {
  const _CapitalGroupDialog({this.group});

  final CapitalGroup? group;

  @override
  State<_CapitalGroupDialog> createState() => _CapitalGroupDialogState();
}

class _CapitalGroupDialogState extends State<_CapitalGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late final _description = TextEditingController(
    text: widget.group?.description ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    Navigator.pop(context, (
      name: name,
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.group == null ? 'Nueva carpeta' : 'Editar carpeta'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'El nombre es obligatorio.'
                  : null,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}
