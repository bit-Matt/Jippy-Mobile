/// A point along a jeepney route (sequence, address, coordinates).
class RoutePoint {
  const RoutePoint({
    required this.id,
    required this.sequence,
    required this.address,
    required this.lat,
    required this.lon,
  });

  final String id;
  final int sequence;
  final String address;
  final double lat;
  final double lon;

  /// Parses from API shape: { "id", "sequence", "address", "point": [lat, lon] }.
  /// Returns null if point is missing or invalid.
  static RoutePoint? fromJson(Map<String, dynamic> json) {
    final pointList = json['point'];
    if (pointList is! List || pointList.length < 2) return null;
    final lat = (pointList[0] is num) ? (pointList[0] as num).toDouble() : null;
    final lon = (pointList[1] is num) ? (pointList[1] as num).toDouble() : null;
    if (lat == null || lon == null) return null;

    final id = json['id']?.toString() ?? '';
    final sequence = json['sequence'] is int ? json['sequence'] as int : 0;
    final address = json['address']?.toString() ?? '';
    return RoutePoint(id: id, sequence: sequence, address: address, lat: lat, lon: lon);
  }
}
