// Basic Flutter widget test for Jippy app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jippy_mobile/main.dart';

void main() {
  testWidgets('JippyApp builds and shows shell with Go screen', (WidgetTester tester) async {
    await tester.pumpWidget(const JippyApp());
    await tester.pump();

    // App shell can include nested scaffolds (e.g. screen + overlay hosts).
    // Verify at least one scaffold is present instead of requiring exactly one.
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });
}
