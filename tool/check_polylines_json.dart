// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:jippy_mobile/utils/polyline_1e6.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'secrets/current_api.json';
  final minPoints = args.length >= 2 ? int.tryParse(args[1]) ?? 50 : 50;

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

  int ok = 0;
  int warn = 0;
  int fail = 0;

  for (final r in routes) {
    if (r is! Map<String, dynamic>) continue;
    final id = (r['id'] ?? '').toString();
    final number = (r['routeNumber'] ?? '').toString();
    final name = (r['routeName'] ?? '').toString();
    final points = r['points'] as Map<String, dynamic>?;
    final to = points?['polylineGoingTo'];
    final back = points?['polylineGoingBack'];

    final toRes = to is String ? tryDecodePolyline6(to) : (points: null, error: 'missing');
    final backRes =
        back is String ? tryDecodePolyline6(back) : (points: null, error: 'missing');

    final toCount = toRes.points?.length ?? 0;
    final backCount = backRes.points?.length ?? 0;

    final toStatus = _statusLabel(toRes, minPoints);
    final backStatus = _statusLabel(backRes, minPoints);

    print('$number $name ($id)');
    print('  goingTo:  $toStatus points=$toCount error=${toRes.error ?? '-'}');
    print('  goingBack:$backStatus points=$backCount error=${backRes.error ?? '-'}');

    final statuses = [toStatus, backStatus];
    if (statuses.any((s) => s == 'FAIL')) {
      fail++;
    } else if (statuses.any((s) => s == 'WARN')) {
      warn++;
    } else {
      ok++;
    }
  }

  print('');
  print('Summary (minPoints=$minPoints): OK=$ok WARN=$warn FAIL=$fail');
  exitCode = fail > 0 ? 1 : 0;
}

String _statusLabel(({List<dynamic>? points, String? error}) res, int minPoints) {
  final pts = res.points;
  if (pts == null) return 'FAIL';
  if (pts.length < minPoints) return 'WARN';
  return 'OK';
}

