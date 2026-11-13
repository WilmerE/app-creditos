import 'package:supabase_flutter/supabase_flutter.dart';

String authErrorMessage(Object error) {
  final raw = error.toString().toLowerCase();
  if (raw.contains('invalid login credentials') ||
      raw.contains('invalid_credentials')) {
    return 'El correo o la contraseña no son correctos.';
  }
  if (raw.contains('email not confirmed') ||
      raw.contains('email_not_confirmed')) {
    return 'Confirma tu correo con el enlace o código enviado antes de iniciar sesión.';
  }
  if (raw.contains('expired') || raw.contains('invalid otp')) {
    return 'El código expiró o no es válido. Solicita uno nuevo.';
  }
  if (raw.contains('network') ||
      raw.contains('socket') ||
      raw.contains('connection') ||
      raw.contains('conexión') ||
      raw.contains('internet') ||
      raw.contains('timed out')) {
    return 'No se pudo conectar. Revisa internet e intenta de nuevo.';
  }
  if (error is AuthException && error.message.isNotEmpty) {
    return error.message;
  }
  return 'No se pudo completar la solicitud. Revisa los datos e intenta de nuevo.';
}

bool validEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
