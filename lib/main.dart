import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/splash_gate.dart';
import 'services/connectivity_service.dart';
import 'services/entitlement_service.dart';
import 'services/notification_service.dart';
import 'services/offline_map_service.dart';
import 'services/subscription_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await ConnectivityService.instance.init();

  // Load any cached premium entitlement before the first frame so gated UI is
  // correct offline. Billing (store connection, product load, restore) is set
  // up in the background and must not block startup.
  await EntitlementService.instance.init();
  unawaited(OfflineMapService.instance.init());
  unawaited(SubscriptionService.instance.init());

  runApp(const JippyApp());
}

class JippyApp extends StatelessWidget {
  const JippyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jippy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashGate(),
    );
  }
}
