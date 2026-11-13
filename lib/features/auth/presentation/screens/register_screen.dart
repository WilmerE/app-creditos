import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_delta_sync.dart';
import 'auth_error_message.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({required this.sync, super.key});

  final SupabaseDeltaSync sync;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _otp = TextEditingController();
  bool _awaitingOtp = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _message;
  String? _error;
  DateTime? _otpExpiresAt;
  DateTime? _resendAvailableAt;
  Timer? _countdownTimer;

  static const _otpLifetime = Duration(hours: 1);
  static const _resendDelay = Duration(seconds: 60);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
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
      _message = null;
    });
    try {
      final response = await widget.sync.register(
        _name.text.trim(),
        _email.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      if (response.session != null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      setState(() {
        _busy = false;
        _awaitingOtp = true;
        _message = 'Enviamos el código de confirmación a tu correo.';
      });
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
      if (response.session != null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      setState(() {
        _busy = false;
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

  Future<void> _resendOtp() async {
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear usuario principal')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_awaitingOtp) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Ingresa tu nombre.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value != null && validEmail(value)
                          ? null
                          : 'Ingresa un correo válido.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 6
                          ? 'Usa al menos 6 caracteres.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmation,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar contraseña',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value != _password.text
                          ? 'Las contraseñas no coinciden.'
                          : null,
                    ),
                  ] else ...[
                    Text(
                      'Ingresa el código de confirmación enviado a ${_email.text.trim()}.',
                    ),
                    const SizedBox(height: 14),
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
                        : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _awaitingOtp ? 'Confirmar correo' : 'Registrarme',
                          ),
                  ),
                  if (_awaitingOtp)
                    TextButton(
                      onPressed: _busy || !_canResend ? null : _resendOtp,
                      child: Text(
                        _canResend
                            ? 'Reenviar código'
                            : 'Reenviar en ${_remaining(_resendAvailableAt)}',
                      ),
                    ),
                  if (_awaitingOtp)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Volver a iniciar sesión'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
