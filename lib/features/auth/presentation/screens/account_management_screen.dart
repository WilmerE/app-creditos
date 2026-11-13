import 'package:flutter/material.dart';

import '../../../../core/network/supabase_delta_sync.dart';
import 'forgot_password_screen.dart';

/// Account settings for the single principal account used by this installation.
class AccountManagementScreen extends StatelessWidget {
  const AccountManagementScreen({required this.sync, super.key});

  final SupabaseDeltaSync sync;

  @override
  Widget build(BuildContext context) {
    final user = sync.currentUser;
    final email = user?.email ?? 'Correo no disponible';
    final emailVerified = user?.emailConfirmedAt != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar usuario')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Usuario principal (root)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Correo de la cuenta'),
                  subtitle: Text(email),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(
                    emailVerified ? Icons.verified_outlined : Icons.info_outline,
                    color: emailVerified
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Verificación del correo'),
                  subtitle: Text(
                    emailVerified ? 'Correo verificado' : 'Correo pendiente de verificación',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Para cambiar la contraseña, verifica que tienes acceso al correo '
                  'de la cuenta. Enviaremos un código OTP y lo ingresarás antes '
                  'de guardar la contraseña nueva.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: user == null || !sync.isConfigured
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ForgotPasswordScreen(
                                sync: sync,
                                initialEmail: email,
                                lockEmail: true,
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.password),
                  label: const Text('Verificar usuario y cambiar contraseña'),
                ),
                if (!sync.isConfigured)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Conecta Supabase para verificar la cuenta y cambiar la contraseña.',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
