import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/map_colors.dart';
import 'screens/splash_gate.dart';
import 'services/entitlement_service.dart';
import 'services/notification_service.dart';
import 'services/subscription_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();

  // Load any cached premium entitlement before the first frame so gated UI is
  // correct offline. Billing (store connection, product load, restore) is set
  // up in the background and must not block startup.
  await EntitlementService.instance.init();
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
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: MapColors.primary,
          secondary: MapColors.secondary,
          tertiary: MapColors.accent,
          surface: MapColors.background,
          onPrimary: Colors.white,
          onSecondary: MapColors.text,
          onSurface: MapColors.text,
        ),
        scaffoldBackgroundColor: MapColors.background,
        canvasColor: MapColors.background,
        useMaterial3: true,
      ),
      home: const SplashGate(),
    );
  }
}
