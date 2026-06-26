import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'jippy_proximity';
  static const int _proximityNotificationId = 1001;

  static const String _offlineMapChannelId = 'jippy_offline_map';
  static const int _offlineMapNotificationId = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    await init();

    var granted = true;

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final result = await androidPlugin?.requestNotificationsPermission();
      granted = result ?? granted;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final iosResult = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = (iosResult ?? granted) && granted;

      final macOsPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      final macOsResult = await macOsPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = (macOsResult ?? granted) && granted;
    }

    return granted;
  }

  Future<void> showProximityNotification({
    required String title,
    required String body,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'Trip proximity alerts',
      channelDescription:
          'Alerts when approaching transfer points or destination.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    await _plugin.show(
      id: _proximityNotificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
    );
  }

  Future<void> showOfflineMapDownloadProgress({
    required int progress,
    required int maxProgress,
    required String body,
  }) async {
    await init();

    final androidDetails = AndroidNotificationDetails(
      _offlineMapChannelId,
      'Offline map downloads',
      channelDescription: 'Progress while downloading offline map tiles.',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: true,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      autoCancel: false,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    await _plugin.show(
      id: _offlineMapNotificationId,
      title: 'Downloading Iloilo map',
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
    );
  }

  Future<void> showOfflineMapDownloadComplete() async {
    await init();
    await _plugin.cancel(id: _offlineMapNotificationId);

    const androidDetails = AndroidNotificationDetails(
      _offlineMapChannelId,
      'Offline map downloads',
      channelDescription: 'Progress while downloading offline map tiles.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    await _plugin.show(
      id: _offlineMapNotificationId,
      title: 'Offline map ready',
      body: 'Iloilo offline map, routes, regions, and images are ready to use.',
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
    );
  }

  Future<void> showOfflineMapDownloadFailed(String message) async {
    await init();
    await _plugin.cancel(id: _offlineMapNotificationId);

    const androidDetails = AndroidNotificationDetails(
      _offlineMapChannelId,
      'Offline map downloads',
      channelDescription: 'Progress while downloading offline map tiles.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    await _plugin.show(
      id: _offlineMapNotificationId,
      title: 'Offline map download failed',
      body: message,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
    );
  }
}
