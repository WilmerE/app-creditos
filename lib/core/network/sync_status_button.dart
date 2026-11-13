import 'package:flutter/material.dart';

import 'supabase_delta_sync.dart';

Future<void> confirmAndSignOut(
  BuildContext context,
  SupabaseDeltaSync sync,
) async {
  final pending = sync.hasPendingChanges;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿Cerrar sesión?'),
      content: Text(
        pending
            ? 'No se puede confirmar que todos los cambios locales estén sincronizados. Si cierras sesión, tendrás que volver a entrar con esta misma cuenta para continuar; los datos permanecerán guardados en este dispositivo.'
            : 'Los datos locales permanecerán guardados en este dispositivo. Para acceder de nuevo necesitarás iniciar sesión.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) await sync.signOut();
}

class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({required this.sync, super.key});

  final SupabaseDeltaSync sync;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: sync,
    builder: (context, _) {
      final (label, icon) = switch (sync.phase) {
        SyncPhase.notConfigured => ('Trabajando localmente', Icons.cloud_off),
        SyncPhase.needsAuthentication => (
          'Trabajando localmente',
          Icons.cloud_off,
        ),
        SyncPhase.accountMismatch => (
          'La base está vinculada a otra cuenta',
          Icons.cloud_off,
        ),
        SyncPhase.syncing => ('Sincronizando', Icons.cloud_sync),
        SyncPhase.synchronized => ('Sincronizado', Icons.cloud_done),
        SyncPhase.offline => ('Trabajando localmente', Icons.cloud_off),
      };
      return IconButton(
        tooltip: label,
        onPressed: () async {
          if (!sync.isConfigured) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Inicia la app con supabase.local.json para habilitar la nube. La base local sigue disponible.',
                ),
              ),
            );
            return;
          }
          if (sync.currentUser == null ||
              sync.phase == SyncPhase.accountMismatch) {
            await showDialog<void>(
              context: context,
              builder: (_) => _SyncAccountDialog(sync: sync),
            );
          } else {
            await sync.synchronize();
          }
        },
        icon: Icon(icon),
      );
    },
  );
}

class _SyncAccountDialog extends StatefulWidget {
  const _SyncAccountDialog({required this.sync});

  final SupabaseDeltaSync sync;

  @override
  State<_SyncAccountDialog> createState() => _SyncAccountDialogState();
}

class _SyncAccountDialogState extends State<_SyncAccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.sync.signIn(
        _email.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      if (response.session == null) {
        setState(() {
          _busy = false;
          _error = 'Revisa tu correo para confirmar la cuenta y luego inicia sesión.';
        });
        return;
      }
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            '$error\nPuedes seguir trabajando con los datos locales e intentar de nuevo cuando tengas conexión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.sync.currentUser;
    return AlertDialog(
      title: Text(
        user == null ? 'Sincronización en la nube' : 'Cuenta de nube',
      ),
      content: user == null
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Iniciar sesión habilita la sincronización. No necesitas conexión para usar los datos guardados en este dispositivo.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Correo'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Text(
              widget.sync.phase == SyncPhase.accountMismatch
                  ? 'La base local está vinculada a otra cuenta. Cierra sesión e inicia con la cuenta original para sincronizar.'
                  : 'Sesión iniciada como ${user.email ?? 'usuario'}.',
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        if (user == null) ...[
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Iniciar sesión'),
          ),
        ] else ...[
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await confirmAndSignOut(context, widget.sync);
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: const Text('Cerrar sesión'),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    Navigator.of(context).pop();
                    await widget.sync.synchronize();
                  },
            child: const Text('Sincronizar ahora'),
          ),
        ],
      ],
    );
  }
}
