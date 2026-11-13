import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_delta_sync.dart';
import 'auth_error_message.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    required this.sync,
    this.initialEmail = '',
    this.lockEmail = false,
    super.key,
  });

  final SupabaseDeltaSync sync;
  final String initialEmail;
  final bool lockEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _message;
  String? _error;
  DateTime? _otpExpiresAt;
  DateTime? _resendAvailableAt;
  Timer? _countdownTimer;

  static const _otpLifetime = Duration(hours: 1);
  static const _resendDelay = Duration(seconds: 60);

  bool get _otpExpired =>
      _otpExpiresAt != null && !DateTime.now().isBefore(_otpExpiresAt!);

  bool get _canResend =>
      _resendAvailableAt != null &&
      !DateTime.now().isBefore(_resendAvailableAt!);

  String _remaining(DateTime? deadline) {
    if (deadline == null) return '--:--';
    final seconds = deadline.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return '00:00';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  void _startOtpCountdown() {
    _countdownTimer?.cancel();
    final now = DateTime.now();
    _otpExpiresAt = now.add(_otpLifetime);
    _resendAvailableAt = now.add(_resendDelay);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (_otpExpired && _canResend) timer.cancel();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirmation.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!validEmail(_email.text)) {
      setState(() => _error = 'Ingresa un correo válido.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.sync.sendPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _codeSent = true;
        _message = 'Revisa tu correo e ingresa el código de recuperación.';
      });
      _startOtpCountdown();
      _otp.clear();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = authErrorMessage(error);
      });
    }
  }

  Future<void> _updatePassword() async {
    if (_otpExpired) {
      setState(() => _error = 'El código expiró. Solicita uno nuevo.');
      return;
    }
    final code = _otp.text.trim();
    if ((code.length != 6 && code.length != 8) || int.tryParse(code) == null) {
      setState(() => _error = 'Ingresa el código numérico de 6 u 8 dígitos.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Usa al menos 6 caracteres para la contraseña.');
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.sync.verifyOtp(
        email: _email.text.trim(),
        token: _otp.text.trim(),
        type: OtpType.recovery,
      );
      await widget.sync.updatePassword(_password.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Contraseña actualizada. Ya puedes iniciar sesión.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = authErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verificar usuario')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Verifica que tienes acceso al correo de la cuenta. Te enviaremos '
                  'un código OTP para confirmar tu identidad y cambiar la contraseña.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  enabled: !_codeSent && !widget.lockEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  Text(
                    _otpExpired
                        ? 'El código expiró.'
                        : 'El código expira en ${_remaining(_otpExpiresAt)}.',
                    style: TextStyle(
                      color: _otpExpired
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  TextField(
                    controller: _otp,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'Código OTP de verificación (8 dígitos)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nueva contraseña',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmation,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar contraseña',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, textAlign: TextAlign.center),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy || !widget.sync.isConfigured
                      ? null
                      : _codeSent
                      ? _updatePassword
                      : _sendCode,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _codeSent ? 'Guardar contraseña' : 'Enviar código',
                        ),
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: _busy || !_canResend ? null : _sendCode,
                    child: Text(
                      _canResend
                          ? 'Reenviar código'
                          : 'Reenviar en ${_remaining(_resendAvailableAt)}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
