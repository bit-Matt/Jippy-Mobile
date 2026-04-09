import 'road_closure_point.dart';

/// A closed-road polygon record from the dashboard public API.
class RoadClosure {
  const RoadClosure({
    required this.id,
    required this.closureName,
    required this.closureDescription,
    required this.points,
  });

  final String id;
  final String closureName;
  final String closureDescription;
  final List<RoadClosurePoint> points;

  /// True when the closure has enough vertices to form a polygon.
  bool get canRenderPolygon => points.length >= 3;

  /// Returns points ordered by sequence (stable for duplicate sequence values).
  List<RoadClosurePoint> get orderedPoints {
    final indexed = points.asMap().entries.toList();
    indexed.sort((a, b) {
      final sequenceCompare = a.value.sequence.compareTo(b.value.sequence);
      if (sequenceCompare != 0) return sequenceCompare;
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList(growable: false);
  }

  /// Parses from API shape:
  /// {
  ///   "id", "closureName", "closureDescription",
  ///   "points": [ { "id", "sequence", "point": [lat, lng] } ]
  /// }
  /// Returns null when required structure is invalid.
  static RoadClosure? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.trim().isEmpty) return null;

    final pointsJson = json['points'];
    if (pointsJson is! List) return null;

    final points = <RoadClosurePoint>[];
    for (final raw in pointsJson) {
      if (raw is! Map<String, dynamic>) return null;
      final point = RoadClosurePoint.fromJson(raw);
      if (point == null) return null;
      points.add(point);
    }

    return RoadClosure(
      id: id,
      closureName: json['closureName']?.toString() ?? '',
      closureDescription: json['closureDescription']?.toString() ?? '',
      points: points,
    );
  }
}
