import 'package:url_launcher/url_launcher.dart';

class ContactLauncher {
  const ContactLauncher._();

  /// Keeps digits only; 8-digit Guatemalan numbers get the 502 country code.
  static String normalizeForWhatsApp(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length == 8 ? '502$digits' : digits;
  }

  static Uri callUri(String phone) =>
      Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));

  static Uri whatsAppUri(String phone) =>
      Uri.parse('https://wa.me/${normalizeForWhatsApp(phone)}');

  static Future<bool> call(String phone) =>
      launchUrl(callUri(phone)).catchError((_) => false);

  static Future<bool> whatsApp(String phone) => launchUrl(
    whatsAppUri(phone),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
}
