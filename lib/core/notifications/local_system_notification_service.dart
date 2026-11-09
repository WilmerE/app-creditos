import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalSystemNotificationService {
  LocalSystemNotificationService._();

  static final LocalSystemNotificationService instance =
      LocalSystemNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() {
    if (!_isAndroid) return Future<void>.value();
    return _initialization ??= _initializeAndroid();
  }

  Future<void> _initializeAndroid() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  Future<void> requestAndroidPermission() async {
    if (!_isAndroid) return;
    await initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> show({
    required String eventKey,
    required String title,
    required String message,
  }) async {
    if (!_isAndroid) return;
    try {
      await initialize();
      await _plugin.show(
        _stableId(eventKey),
        title,
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'operational_alerts',
            'Alertas operativas',
            channelDescription:
                'Avisos de mora, cobros pendientes y cambios de tarjetas.',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
        ),
        payload: eventKey,
      );
    } on Object {
      // La alerta interna en SQLite sigue disponible aunque Android no permita
      // mostrar el aviso (por ejemplo, si el usuario negó el permiso).
    }
  }

  int _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
