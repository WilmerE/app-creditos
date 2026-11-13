import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_delta_sync.dart';
import 'auth_error_message.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.sync, super.key});

  final SupabaseDeltaSync sync;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  bool _emailNeedsConfirmation = false;
  bool _awaitingOtp = false;
  String? _error;
  String? _message;
  final _otp = TextEditingController();
  DateTime? _otpExpiresAt;
  DateTime? _resendAvailableAt;
  Timer? _countdownTimer;
  late Future<bool> _rootAccountAvailability;

  static const _otpLifetime = Duration(hours: 1);
  static const _resendDelay = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _rootAccountAvailability = widget.sync.isRootAccountAvailable();
  }

  Future<void> _openRootRegistration() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisterScreen(sync: widget.sync),
      ),
    );
    if (!mounted) return;
    setState(() {
      _rootAccountAvailability = widget.sync.isRootAccountAvailable();
    });
  }

  void _refreshRootAccountAvailability() {
    setState(() {
      _rootAccountAvailability = widget.sync.isRootAccountAvailable();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

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

  Future<void> _submit() async {
    if (_awaitingOtp) {
      await _verifyOtp();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.sync.signIn(
        _email.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      if (result.session == null) {
        setState(() {
          _busy = false;
          _error = 'Confirma tu cuenta con el enlace enviado a tu correo.';
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _emailNeedsConfirmation =
            error.toString().toLowerCase().contains('email not confirmed') ||
            error.toString().toLowerCase().contains('email_not_confirmed');
        _error = authErrorMessage(error);
      });
    }
  }

  Future<void> _sendConfirmationCode() async {
    if (!validEmail(_email.text)) {
      setState(() => _error = 'Ingresa primero el correo de tu cuenta.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.sync.resendSignupConfirmation(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _awaitingOtp = true;
        _emailNeedsConfirmation = false;
        _message = 'Enviamos un nuevo código de confirmación.';
      });
      _otp.clear();
      _startOtpCountdown();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = authErrorMessage(error);
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpExpired) {
      setState(() => _error = 'El código expiró. Solicita uno nuevo.');
      return;
    }
    final code = _otp.text.trim();
    if ((code.length != 6 && code.length != 8) || int.tryParse(code) == null) {
      setState(() => _error = 'Ingresa el código numérico de 6 u 8 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.sync.verifyOtp(
        email: _email.text.trim(),
        token: _otp.text.trim(),
        type: OtpType.signup,
      );
      if (!mounted) return;
      if (response.session != null) return;
      setState(() {
        _busy = false;
        _awaitingOtp = false;
        _message = 'Correo confirmado. Ya puedes iniciar sesión.';
      });
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
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Llave en Mano',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'El primer inicio requiere internet. Después, tu sesión guardada te permitirá trabajar sin cobertura.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value != null && validEmail(value)
                        ? null
                        : 'Ingresa un correo válido.',
                  ),
                  const SizedBox(height: 14),
                  if (_awaitingOtp) ...[
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
                    const SizedBox(height: 8),
                    TextField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      decoration: const InputDecoration(
                        labelText: 'Código OTP (8 dígitos)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Ocultar contraseña'
                              : 'Mostrar contraseña',
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Ingresa tu contraseña.'
                          : null,
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _ErrorBox(message: _error!),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy || !widget.sync.isConfigured
                        ? null
                        : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _awaitingOtp
                                ? 'Confirmar correo'
                                : 'Iniciar sesión',
                          ),
                  ),
                  if (_emailNeedsConfirmation)
                    TextButton(
                      onPressed: _busy ? null : _sendConfirmationCode,
                      child: const Text('Enviar código de confirmación'),
                    ),
                  if (_awaitingOtp)
                    TextButton(
                      onPressed: _busy || !_canResend
                          ? null
                          : _sendConfirmationCode,
                      child: Text(
                        _canResend
                            ? 'Reenviar código'
                            : 'Reenviar en ${_remaining(_resendAvailableAt)}',
                      ),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ForgotPasswordScreen(
                                sync: widget.sync,
                                initialEmail: _email.text.trim(),
                              ),
                            ),
                          ),
                    child: const Text('Olvidé mi contraseña'),
                  ),
                  FutureBuilder<bool>(
                    future: _rootAccountAvailability,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return TextButton.icon(
                          onPressed: _refreshRootAccountAvailability,
                          icon: const Icon(Icons.refresh),
                          label: const Text(
                            'Reintentar verificación de usuario principal',
                          ),
                        );
                      }
                      if (snapshot.data != true) {
                        return const SizedBox.shrink();
                      }
                      return OutlinedButton.icon(
                        onPressed: _busy ? null : _openRootRegistration,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Crear usuario principal'),
                      );
                    },
                  ),
                  if (!widget.sync.isConfigured) ...[
                    const SizedBox(height: 16),
                    const _ErrorBox(
                      message: 'Falta configurar Supabase para autenticar. Inicia la app con SUPABASE_URL y SUPABASE_API_KEY.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}
