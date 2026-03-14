import 'package:flutter/material.dart';

import 'core/theme/map_colors.dart';
import 'screens/map_screen.dart';

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
          surface: MapColors.background,
          onPrimary: MapColors.text,
          onSecondary: MapColors.text,
          onSurface: MapColors.text,
        ),
        scaffoldBackgroundColor: MapColors.background,
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
