import 'package:flutter_test/flutter_test.dart';
import 'package:jippy_mobile/core/config/trip_simulator_config.dart';

void main() {
  group('kTripSimulatorEnabled', () {
    test('is enabled in debug test runs', () {
      expect(kTripSimulatorEnabled, isTrue);
    });
  });
}
