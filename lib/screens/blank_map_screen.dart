import 'package:flutter/material.dart';

import '../core/theme/map_colors.dart';

class BlankMapScreen extends StatelessWidget {
  const BlankMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MapColors.background,
      body: SizedBox.expand(),
    );
  }
}