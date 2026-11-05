import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/client.dart';
import '../bloc/client_bloc.dart';
import '../widgets/client_photo_picker.dart';

class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, this.client});

  /// `null` creates a new client.
  final Client? client;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  static final _phoneRegex = RegExp(r'^\+?[0-9 ()\-]{7,20}$');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _dpi;
  late final TextEditingController _dpiFolder;
  late final TextEditingController _alias;
  late final List<TextEditingController> _phones;
  String? _pendingPhoto;
  bool _removePhoto = false;

  bool get _isEditing => widget.client != null;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    _name = TextEditingController(text: c?.fullName);
    _address = TextEditingController(text: c?.address);
    _dpi = TextEditingController(text: c?.dpi);
    _dpiFolder = TextEditingController(text: c?.dpiFolder);
    _alias = TextEditingController(text: c?.alias);
    _phones = [
      for (final phone in c?.phones ?? const <String>[])
        TextEditingController(text: phone),
    ];
    if (_phones.isEmpty) _phones.add(TextEditingController());
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _dpi,
      _dpiFolder,
      _alias,
      ..._phones,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(String text) {
    final value = text.trim();
    return value.isEmpty ? null : value;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final phones = _phones
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final existing = widget.client;
    final client = Client(
      id: existing?.id ?? const Uuid().v4(),
      fullName: _name.text.trim(),
      address: _address.text.trim(),
      phones: phones,
      dpi: _nullIfEmpty(_dpi.text),
      dpiFolder: _nullIfEmpty(_dpiFolder.text),
      alias: _nullIfEmpty(_alias.text),
      photoPath: _removePhoto ? null : existing?.photoPath,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    context.read<ClientBloc>().add(
      ClientSaved(client, newPhotoSourcePath: _pendingPhoto),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ClientBloc, ClientState>(
      listenWhen: (previous, current) =>
          previous.saveStatus != current.saveStatus &&
          (current.saveStatus == ClientSaveStatus.success ||
              current.saveStatus == ClientSaveStatus.failure),
      listener: (context, state) {
        if (state.saveStatus == ClientSaveStatus.success) {
          Navigator.of(context).pop();
        } else if (state.message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message!)));
          context.read<ClientBloc>().add(const ClientMessageCleared());
        }
      },
      buildWhen: (previous, current) =>
          previous.saveStatus != current.saveStatus,
      builder: (context, state) {
        final saving = state.saveStatus == ClientSaveStatus.saving;
        return Scaffold(
          appBar: AppBar(
            title: Text(_isEditing ? 'Editar cliente' : 'Nuevo cliente'),
            actions: [
              TextButton.icon(
                onPressed: saving ? null : _submit,
                icon: const Icon(Icons.check),
                label: const Text('Guardar'),
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: ClientPhotoPicker(
                        name: _name.text,
                        currentPhotoPath: _removePhoto
                            ? null
                            : widget.client?.photoPath,
                        pendingPhotoPath: _pendingPhoto,
                        onPicked: (path) => setState(() {
                          _pendingPhoto = path;
                          _removePhoto = false;
                        }),
                        onRemoved: () => setState(() {
                          _pendingPhoto = null;
                          _removePhoto = true;
                        }),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'El nombre es obligatorio'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _address,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Dirección / Ubicación *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'La dirección es obligatoria'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Teléfonos',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _phones.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _phones[i],
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: i == 0
                                      ? 'Teléfono principal'
                                      : 'Teléfono ${i + 1}',
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final text = v?.trim() ?? '';
                                  if (text.isEmpty) return null;
                                  return _phoneRegex.hasMatch(text)
                                      ? null
                                      : 'Número no válido';
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'Eliminar teléfono',
                              onPressed: _phones.length == 1
                                  ? null
                                  : () => setState(
                                      () => _phones.removeAt(i).dispose(),
                                    ),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () => _phones.add(TextEditingController()),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar teléfono'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _dpi,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'DPI / Documento',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _dpiFolder,
                      decoration: const InputDecoration(
                        labelText: 'Carpeta DPI (ruta o referencia)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _alias,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Referencia / Alias',
                        hintText: 'YOLI DE DON NERY',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: saving ? null : _submit,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Guardar cliente'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
