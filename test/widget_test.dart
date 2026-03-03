// Basic Flutter widget test for Jippy app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jippy_mobile/main.dart';

void main() {
  testWidgets('JippyApp builds and shows map screen', (WidgetTester tester) async {
    await tester.pumpWidget(const JippyApp());
    await tester.pump();

    // MapScreen is the home; FlutterMap is the main map widget.
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
