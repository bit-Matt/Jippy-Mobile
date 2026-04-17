import 'package:flutter/material.dart';

/// Semi-transparent overlay with a circular progress indicator while routes load.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black26,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
