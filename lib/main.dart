import 'package:flutter/material.dart';

import 'core/notifications/local_system_notification_service.dart';
import 'app.dart';
import 'injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalSystemNotificationService.instance.initialize();
  await configureDependencies();

  runApp(const CreditosApp());
}
