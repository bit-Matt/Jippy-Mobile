import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/routes_and_stations_data.dart';

/// Dashboard API base URL (no trailing slash). Used for routes and Valhalla proxy.
// const String apiBaseUrl = 'https://jippy.shinosawa-laboratories.dev'; // Production
const String apiBaseUrl = 'http://172.24.0.1:3000'; // Local Development

/// Public API URL for all routes and regions (dashboard API shape).
// const String routesApiUrl = 'http://localhost:3000/api/public/all'; // Production
const String routesApiUrl = '$apiBaseUrl/api/public/all';

/// Timeout for the routes API request.
const Duration _routesApiTimeout = Duration(seconds: 15);

/// Path to the sample routes/stations JSON asset (dashboard API shape).
const String sampleRoutesAssetPath =
    'assets/sample_routes/sample_api_data.json';

/// Fetches route and station data from the server API.
/// Returns parsed [RoutesAndStationsData] on success.
/// Throws on network error, non-200 response, or parse failure (caller can fall back to [loadSampleMapData]).
Future<RoutesAndStationsData> loadRoutesFromApi() async {
  final response = await http
      .get(Uri.parse(routesApiUrl))
      .timeout(_routesApiTimeout);

  if (response.statusCode != 200) {
    throw Exception('Routes API returned ${response.statusCode}');
  }

  final json = jsonDecode(response.body);
  if (json is! Map<String, dynamic>) {
    throw Exception('Routes API returned invalid JSON');
  }

  return RoutesAndStationsData.fromJson(json);
}

/// Loads the sample map data from assets and parses it into [RoutesAndStationsData].
/// Returns empty data on load or parse error.
Future<RoutesAndStationsData> loadSampleMapData() async {
  try {
    final String jsonString = await rootBundle.loadString(
      sampleRoutesAssetPath,
    );
    final Map<String, dynamic> json =
        jsonDecode(jsonString) as Map<String, dynamic>;
    return RoutesAndStationsData.fromJson(json);
  } catch (_) {
    return const RoutesAndStationsData(routes: [], stations: []);
  }
}
