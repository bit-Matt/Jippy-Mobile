import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/routes_and_stations_data.dart';

/// Path to the sample routes/stations JSON asset (dashboard API shape).
const String sampleRoutesAssetPath = 'assets/sample_routes/sample_api_data.json';

/// Loads the sample map data from assets and parses it into [RoutesAndStationsData].
/// Returns empty data on load or parse error.
Future<RoutesAndStationsData> loadSampleMapData() async {
  try {
    final String jsonString =
        await rootBundle.loadString(sampleRoutesAssetPath);
    final Map<String, dynamic> json = jsonDecode(jsonString) as Map<String, dynamic>;
    return RoutesAndStationsData.fromJson(json);
  } catch (_) {
    return const RoutesAndStationsData(routes: [], stations: []);
  }
}
