/// Compile-time configuration for the Go screen trip simulator.
library;

import 'package:flutter/foundation.dart';

/// Compile-time opt-in for the trip simulator in release APKs.
///
/// Build with `--dart-define=JIPPY_TRIP_SIMULATOR=true` for internal QA or
/// presentation APKs. Omit this flag for Play-distributed AAB/release builds.
const bool _kTripSimulatorDartDefine = bool.fromEnvironment(
  'JIPPY_TRIP_SIMULATOR',
  defaultValue: false,
);

/// Whether the trip simulator UI and synthetic GPS routing are available.
///
/// Enabled in debug builds and in release APKs built with
/// `JIPPY_TRIP_SIMULATOR=true`. Never enabled in a normal production build.
bool get kTripSimulatorEnabled => kDebugMode || _kTripSimulatorDartDefine;
