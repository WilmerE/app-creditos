import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class LocalSystemNotificationService {
  LocalSystemNotificationService._();

  static final LocalSystemNotificationService instance =
      LocalSystemNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  bool _timeZonesInitialized = false;

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
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  Future<void> scheduleDailyCollectionReminder({
    required int hour,
    required int minute,
  }) async {
    if (!_isAndroid) return;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null &&
        await android.canScheduleExactNotifications() != true) {
      throw StateError(
        'Android no concedió permiso para programar alarmas exactas.',
      );
    }
    if (!_timeZonesInitialized) {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Guatemala'));
      _timeZonesInitialized = true;
    }
    final now = tz.TZDateTime.now(tz.local);
    var firstReminder = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!firstReminder.isAfter(now)) {
      firstReminder = firstReminder.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      0x43524544,
      'Recordatorio de cobros',
      'Revisa las cuotas pendientes de hoy en el dashboard.',
      firstReminder,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'collection_reminders',
          'Recordatorios de cobro',
          channelDescription:
              'Recordatorios diarios de las cuotas de cobro pendientes.',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_collection_reminder',
    );
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
    } on Object catch (error, stackTrace) {
      debugPrint('No se pudo mostrar una notificación local: $error');
      debugPrintStack(stackTrace: stackTrace);
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
