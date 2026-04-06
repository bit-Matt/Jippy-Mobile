/// A polygon vertex for a road closure area.
class RoadClosurePoint {
  const RoadClosurePoint({
    required this.id,
    required this.sequence,
    required this.lat,
    required this.lng,
  });

  final String id;
  final int sequence;
  final double lat;
  final double lng;

  /// Parses from API shape: { "id", "sequence", "point": [lat, lng] }.
  /// Returns null if shape is invalid.
  static RoadClosurePoint? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.trim().isEmpty) return null;

    final rawSequence = json['sequence'];
    if (rawSequence is! num) return null;
    final sequence = rawSequence.toInt();

    final tuple = json['point'];
    if (tuple is! List || tuple.length < 2) return null;
    final lat = tuple[0] is num ? (tuple[0] as num).toDouble() : null;
    final lng = tuple[1] is num ? (tuple[1] as num).toDouble() : null;
    if (lat == null || lng == null) return null;

    return RoadClosurePoint(id: id, sequence: sequence, lat: lat, lng: lng);
  }
}
