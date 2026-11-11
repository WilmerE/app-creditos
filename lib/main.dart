import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/secure_supabase_session_storage.dart';
import 'core/notifications/local_system_notification_service.dart';
import 'app.dart';
import 'injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalSystemNotificationService.instance.initialize();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseApiKey = String.fromEnvironment('SUPABASE_API_KEY');
  SupabaseClient? supabaseClient;
  if (supabaseUrl.isNotEmpty && supabaseApiKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseApiKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSupabaseSessionStorage(
            persistSessionKey:
                'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
          ),
        ),
      );
      supabaseClient = Supabase.instance.client;
    } on Object {
      // Cloud configuration must not prevent the local database from opening.
    }
  }
  await configureDependencies(supabaseClient: supabaseClient);

  runApp(const CreditosApp());
}
