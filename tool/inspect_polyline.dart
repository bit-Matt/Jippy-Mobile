// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:jippy_mobile/utils/polyline_1e6.dart';
import 'package:latlong2/latlong.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : 'secrets/current_api.json';

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exitCode = 2;
    return;
  }

  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final data = root['data'] as Map<String, dynamic>?;
  final routes = data?['routes'] as List<dynamic>?;
  if (routes == null || routes.isEmpty) {
    stderr.writeln('No routes found in $path');
    exitCode = 2;
    return;
  }

  final route = routes.first as Map<String, dynamic>;
  final id = (route['id'] ?? '').toString();
  final number = (route['routeNumber'] ?? '').toString();
  final name = (route['routeName'] ?? '').toString();

  final points = route['points'] as Map<String, dynamic>?;
  if (points == null) {
    stderr.writeln('Route has no points object.');
    exitCode = 2;
    return;
  }

  inspectOne(id: id, label: '$number $name goingTo', encoded: points['polylineGoingTo']);
  inspectOne(id: id, label: '$number $name goingBack', encoded: points['polylineGoingBack']);
}

void inspectOne({required String id, required String label, required dynamic encoded}) {
  if (encoded is! String || encoded.trim().isEmpty) {
    print('$label: no polyline');
    return;
  }

  final decoded = decodeApiRoutePolyline(encoded);
  if (decoded == null) {
    print('$label: decode FAILED (id=$id, len=${encoded.length})');
    return;
  }

  final bounds = _bounds(decoded);
  final center = LatLng(
    (bounds.minLat + bounds.maxLat) / 2,
    (bounds.minLon + bounds.maxLon) / 2,
  );

  print('$label: decodedPoints=${decoded.length} id=$id');
  print('  lat=[${bounds.minLat}, ${bounds.maxLat}] lon=[${bounds.minLon}, ${bounds.maxLon}]');
  print('  center=${center.latitude},${center.longitude}');
}

({double minLat, double maxLat, double minLon, double maxLon}) _bounds(List<LatLng> pts) {
  double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
  for (final p in pts) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLon) minLon = p.longitude;
    if (p.longitude > maxLon) maxLon = p.longitude;
  }
  return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
}

