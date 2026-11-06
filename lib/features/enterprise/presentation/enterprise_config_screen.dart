import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../injection_container.dart';
import '../data/enterprise_config_repository.dart';
import '../domain/enterprise_config.dart';

class EnterpriseConfigScreen extends StatelessWidget {
  const EnterpriseConfigScreen({super.key, this.repository});

  final EnterpriseConfigRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repository =
        this.repository ?? EnterpriseConfigRepository(getIt<AppDatabase>());
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración empresarial')),
      body: StreamBuilder<EnterpriseConfig>(
        stream: repository.watch(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudo cargar la configuración empresarial.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _ConfigForm(repository: repository, initial: snapshot.data!);
        },
      ),
    );
  }
}

class _ConfigForm extends StatefulWidget {
  const _ConfigForm({required this.repository, required this.initial});

  final EnterpriseConfigRepository repository;
  final EnterpriseConfig initial;

  @override
  State<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends State<_ConfigForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _nit = TextEditingController(text: widget.initial.nit);
  late final _email = TextEditingController(text: widget.initial.email);
  late final _bank = TextEditingController(text: widget.initial.bankAccount);
  late bool _showPhone = widget.initial.showPhone;
  late bool _showNit = widget.initial.showNit;
  late bool _showEmail = widget.initial.showEmail;
  late bool _showBank = widget.initial.showBankAccount;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _nit.dispose();
    _email.dispose();
    _bank.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.save(
        EnterpriseConfig(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          nit: _nit.text.trim(),
          email: _email.text.trim(),
          bankAccount: _bank.text.trim(),
          showPhone: _showPhone,
          showNit: _showNit,
          showEmail: _showEmail,
          showBankAccount: _showBank,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuración guardada.')));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar la configuración empresarial.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    bool visible,
    ValueChanged<bool> onChanged,
  ) {
    return Column(
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Mostrar $label en la tarjeta'),
          value: visible,
          onChanged: (value) => onChanged(value ?? false),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la empresa',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Ingrese el nombre de la empresa.'
                    : null,
              ),
              _field(
                'Teléfono',
                _phone,
                _showPhone,
                (v) => setState(() => _showPhone = v),
              ),
              _field(
                'NIT',
                _nit,
                _showNit,
                (v) => setState(() => _showNit = v),
              ),
              _field(
                'Correo',
                _email,
                _showEmail,
                (v) => setState(() => _showEmail = v),
              ),
              _field(
                'No. de cuenta bancaria',
                _bank,
                _showBank,
                (v) => setState(() => _showBank = v),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
