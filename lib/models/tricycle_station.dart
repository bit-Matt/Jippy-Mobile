/// A tricycle station location within a region (from dashboard API).
class TricycleStation {
  const TricycleStation({
    required this.id,
    required this.address,
    required this.lat,
    required this.lon,
  });

  final String id;
  final String address;
  final double lat;
  final double lon;

  /// Parses from API shape: { "id", "address", "point": [lat, lon] }.
  /// Returns null if point is missing or invalid.
  static TricycleStation? fromJson(Map<String, dynamic> json) {
    final pointList = json['point'];
    if (pointList is! List || pointList.length < 2) return null;
    final lat = (pointList[0] is num) ? (pointList[0] as num).toDouble() : null;
    final lon = (pointList[1] is num) ? (pointList[1] as num).toDouble() : null;
    if (lat == null || lon == null) return null;

    final id = json['id']?.toString() ?? '';
    final address = json['address']?.toString() ?? '';
    return TricycleStation(id: id, address: address, lat: lat, lon: lon);
  }
}
