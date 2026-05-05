import 'package:flutter/material.dart';

import 'core/theme/map_colors.dart';
import 'screens/app_shell.dart';

void main() {
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
      home: const AppShell(),
    );
  }
}
