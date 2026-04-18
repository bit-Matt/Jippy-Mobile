/// Parsed shape for POST /api/public/navigate response suggestions.
class NavigateSuggestionsResponse {
  const NavigateSuggestionsResponse({
    required this.ok,
    required this.suggestions,
  });

  final bool ok;
  final List<NavigateSuggestion> suggestions;

  static NavigateSuggestionsResponse fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true;
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      return NavigateSuggestionsResponse(ok: ok, suggestions: const []);
    }

    final rawSuggestions = data['suggestions'];
    if (rawSuggestions is! List) {
      return NavigateSuggestionsResponse(ok: ok, suggestions: const []);
    }

    final suggestions = <NavigateSuggestion>[];
    for (final item in rawSuggestions) {
      if (item is! Map<String, dynamic>) continue;
      final parsed = NavigateSuggestion.fromJson(item);
      if (parsed != null) suggestions.add(parsed);
    }

    return NavigateSuggestionsResponse(ok: ok, suggestions: suggestions);
  }
}

class NavigateSuggestion {
  const NavigateSuggestion({
    required this.rawLabel,
    required this.label,
    required this.route,
  });

  final String rawLabel;
  final NavigateSuggestionLabel label;
  final NavigateRoute route;

  static NavigateSuggestion? fromJson(Map<String, dynamic> json) {
    final routeJson = json['route'];
    if (routeJson is! Map<String, dynamic>) return null;

    final route = NavigateRoute.fromJson(routeJson);
    if (route.legs.isEmpty) return null;

    final rawLabel = json['label']?.toString() ?? '';
    return NavigateSuggestion(
      rawLabel: rawLabel,
      label: parseNavigateSuggestionLabel(rawLabel),
      route: route,
    );
  }

  String get labelText {
    return switch (label) {
      NavigateSuggestionLabel.fastest => 'Fastest',
      NavigateSuggestionLabel.simplest => 'Simplest',
      NavigateSuggestionLabel.explorer => 'Explorer',
      NavigateSuggestionLabel.leastWalking => 'Least Walking',
      NavigateSuggestionLabel.unknown =>
        rawLabel.trim().isEmpty ? 'Route' : rawLabel.trim(),
    };
  }

  double get totalDistanceMeters => route.totalDistanceMeters;

  double get totalDurationMinutes => route.totalDurationMinutes;

  int get boardCount {
    var count = 0;
    for (final leg in route.legs) {
      for (final instruction in leg.instructions) {
        if (instruction.maneuverType == NavigateManeuverType.board) {
          count += 1;
        }
      }
    }
    return count;
  }

  int get transferCount {
    if (boardCount > 0) {
      return boardCount > 1 ? boardCount - 1 : 0;
    }

    final transitLegCount = route.legs
        .where((leg) => leg.type != NavigateLegType.walk)
        .length;
    return transitLegCount > 1 ? transitLegCount - 1 : 0;
  }
}

class NavigateRoute {
  const NavigateRoute({required this.legs});

  final List<NavigateLeg> legs;

  static NavigateRoute fromJson(Map<String, dynamic> json) {
    final rawLegs = json['legs'];
    if (rawLegs is! List) return const NavigateRoute(legs: []);

    final legs = <NavigateLeg>[];
    for (final item in rawLegs) {
      if (item is! Map<String, dynamic>) continue;
      final parsed = NavigateLeg.fromJson(item);
      if (parsed != null) legs.add(parsed);
    }

    return NavigateRoute(legs: legs);
  }

  double get totalDistanceMeters {
    var total = 0.0;
    for (final leg in legs) {
      total += leg.distanceMeters;
    }
    return total;
  }

  double get totalDurationMinutes {
    var total = 0.0;
    for (final leg in legs) {
      total += leg.durationMinutes;
    }
    return total;
  }
}

class NavigateLeg {
  const NavigateLeg({
    required this.type,
    required this.routeName,
    required this.polyline,
    required this.colorHex,
    required this.distanceMeters,
    required this.durationMinutes,
    required this.instructions,
    required this.bbox,
  });

  final NavigateLegType type;
  final String routeName;
  final String polyline;
  final String? colorHex;
  final double distanceMeters;
  final double durationMinutes;
  final List<NavigateInstruction> instructions;
  final List<NavigatePoint> bbox;

  static NavigateLeg? fromJson(Map<String, dynamic> json) {
    final routeName = json['route_name']?.toString().trim() ?? '';
    final polyline = json['polyline']?.toString().trim() ?? '';

    final rawInstructions = json['instructions'];
    final instructions = <NavigateInstruction>[];
    if (rawInstructions is List) {
      for (final item in rawInstructions) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = NavigateInstruction.fromJson(item);
        if (parsed != null) instructions.add(parsed);
      }
    }

    final bbox = _parseBBox(json['bbox']);

    return NavigateLeg(
      type: parseNavigateLegType(json['type']?.toString()),
      routeName: routeName,
      polyline: polyline,
      colorHex: _normalizeNullableString(json['color']),
      distanceMeters: _toDouble(json['distance']) ?? 0,
      durationMinutes: _toDouble(json['duration']) ?? 0,
      instructions: instructions,
      bbox: bbox,
    );
  }
}

class NavigateInstruction {
  const NavigateInstruction({required this.text, required this.maneuverType});

  final String text;
  final NavigateManeuverType maneuverType;

  static NavigateInstruction? fromJson(Map<String, dynamic> json) {
    final text = json['text']?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    return NavigateInstruction(
      text: text,
      maneuverType: parseNavigateManeuverType(
        json['maneuver_type']?.toString(),
      ),
    );
  }
}

class NavigatePoint {
  const NavigatePoint({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

enum NavigateSuggestionLabel {
  fastest,
  simplest,
  explorer,
  leastWalking,
  unknown,
}

enum NavigateLegType { walk, jeepney, tricycle, unknown }

enum NavigateManeuverType { board, alight, depart, turn, arrive, unknown }

NavigateSuggestionLabel parseNavigateSuggestionLabel(String? raw) {
  final v = _normalizeEnumValue(raw);
  return switch (v) {
    'fastest' => NavigateSuggestionLabel.fastest,
    'simplest' => NavigateSuggestionLabel.simplest,
    'explorer' => NavigateSuggestionLabel.explorer,
    'least_walking' => NavigateSuggestionLabel.leastWalking,
    _ => NavigateSuggestionLabel.unknown,
  };
}

NavigateLegType parseNavigateLegType(String? raw) {
  final v = _normalizeEnumValue(raw);
  return switch (v) {
    'walk' => NavigateLegType.walk,
    'jeepney' => NavigateLegType.jeepney,
    'tricycle' => NavigateLegType.tricycle,
    _ => NavigateLegType.unknown,
  };
}

NavigateManeuverType parseNavigateManeuverType(String? raw) {
  final v = _normalizeEnumValue(raw);
  return switch (v) {
    'board' => NavigateManeuverType.board,
    'alight' => NavigateManeuverType.alight,
    'depart' => NavigateManeuverType.depart,
    'turn' => NavigateManeuverType.turn,
    'arrive' => NavigateManeuverType.arrive,
    _ => NavigateManeuverType.unknown,
  };
}

String _normalizeEnumValue(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
}

String? _normalizeNullableString(dynamic value) {
  final s = value?.toString().trim();
  if (s == null || s.isEmpty || s.toLowerCase() == 'null') {
    return null;
  }
  return s;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

List<NavigatePoint> _parseBBox(dynamic value) {
  if (value is! List) return const [];

  final points = <NavigatePoint>[];
  for (final item in value) {
    if (item is List && item.length >= 2) {
      final lat = _toDouble(item[0]);
      final lng = _toDouble(item[1]);
      if (lat == null || lng == null) continue;
      points.add(NavigatePoint(lat: lat, lng: lng));
      continue;
    }

    if (item is Map<String, dynamic>) {
      final lat = _toDouble(item['lat'] ?? item['latitude']);
      final lng = _toDouble(item['lng'] ?? item['lon'] ?? item['longitude']);
      if (lat == null || lng == null) continue;
      points.add(NavigatePoint(lat: lat, lng: lng));
    }
  }

  return points;
}
