import 'tricycle_region_point.dart';
import 'tricycle_station.dart';

/// An official tricycle service region with polygon boundary and waiting stations.
class TricycleRegion {
  const TricycleRegion({
    required this.id,
    required this.regionName,
    required this.regionColor,
    required this.regionShape,
    required this.points,
    required this.stations,
  });

  final String id;
  final String regionName;
  final String regionColor;
  final String regionShape;
  final List<TricycleRegionPoint> points;
  final List<TricycleStation> stations;

  bool get canRenderPolygon =>
      regionShape.toLowerCase() == 'polygon' && points.length >= 3;

  List<TricycleRegionPoint> get orderedPoints {
    final indexed = points.asMap().entries.toList();
    indexed.sort((a, b) {
      final sequenceCompare = a.value.sequence.compareTo(b.value.sequence);
      if (sequenceCompare != 0) return sequenceCompare;
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList(growable: false);
  }

  /// Parses from API shape under `data.regions[]`.
  static TricycleRegion? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.trim().isEmpty) return null;

    final pointsJson = json['points'];
    if (pointsJson is! List) return null;

    final points = <TricycleRegionPoint>[];
    for (final raw in pointsJson) {
      if (raw is! Map<String, dynamic>) continue;
      final point = TricycleRegionPoint.fromJson(raw);
      if (point != null) points.add(point);
    }

    final stations = <TricycleStation>[];
    final stationsJson = json['stations'];
    if (stationsJson is List) {
      for (final raw in stationsJson) {
        if (raw is! Map<String, dynamic>) continue;
        final station = TricycleStation.fromJson(raw);
        if (station != null) stations.add(station);
      }
    }

    return TricycleRegion(
      id: id,
      regionName: json['regionName']?.toString() ?? '',
      regionColor: json['regionColor']?.toString() ?? '',
      regionShape: json['regionShape']?.toString() ?? 'Polygon',
      points: points,
      stations: stations,
    );
  }
}
