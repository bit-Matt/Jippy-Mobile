import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Nominatim search / reverse-geocode client with light caching and request spacing.
///
/// See [secrets/docs/searchbar-step-by-step.md] for policy (User-Agent, rate limits).
class GeocodingService {
  GeocodingService({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  static const String _baseHost = 'nominatim.openstreetmap.org';
  static const String userAgent =
      'Jippy-Mobile/1.0.0 (capstone; contact: https://jippy.shinosawa-laboratories.dev)';

  /// Iloilo bounded search area: min_lon, max_lat, max_lon, min_lat.
  static const String iloiloViewBox = '122.019,11.628,123.336,10.407';

  static const double _iloiloMinLat = 10.65;
  static const double _iloiloMaxLat = 10.78;
  static const double _iloiloMinLon = 122.50;
  static const double _iloiloMaxLon = 122.60;

  final Map<String, List<NominatimSearchHit>> _searchCache = {};
  final Map<String, String> _reverseCache = {};
  static const int _maxCacheEntries = 40;

  DateTime? _nextAllowedRequest;

  Future<void> _respectRateLimit() async {
    final now = DateTime.now();
    if (_nextAllowedRequest != null && now.isBefore(_nextAllowedRequest!)) {
      await Future<void>.delayed(_nextAllowedRequest!.difference(now));
    }
    // Public instance policy: stay safely under 1 req/s.
    _nextAllowedRequest = DateTime.now().add(const Duration(milliseconds: 1100));
  }

  bool isWithinIloiloServiceArea(LatLng point) {
    return point.latitude >= _iloiloMinLat &&
        point.latitude <= _iloiloMaxLat &&
        point.longitude >= _iloiloMinLon &&
        point.longitude <= _iloiloMaxLon;
  }

  Future<List<NominatimSearchHit>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final cacheKey = trimmed.toLowerCase();
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    await _respectRateLimit();
    final uri = Uri.https(_baseHost, '/search', {
      'q': trimmed,
      'format': 'json',
      'countrycodes': 'ph',
      'viewbox': iloiloViewBox,
      'bounded': '1',
      'limit': '8',
    });

    final response = await _client.get(
      uri,
      headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw GeocodingException(
        'Search failed (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const GeocodingException('Unexpected search response');
    }

    final hits = <NominatimSearchHit>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      final name = item['display_name']?.toString();
      if (lat == null || lon == null || name == null || name.isEmpty) continue;
      hits.add(
        NominatimSearchHit(
          displayName: name,
          point: LatLng(lat, lon),
        ),
      );
    }

    _evictIfNeeded(_searchCache, _maxCacheEntries);
    _searchCache[cacheKey] = hits;
    return hits;
  }

  Future<String> reverseLabel(LatLng point) async {
    final key =
        '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
    final cached = _reverseCache[key];
    if (cached != null) return cached;

    await _respectRateLimit();
    final uri = Uri.https(_baseHost, '/reverse', {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'format': 'jsonv2',
      'countrycodes': 'ph',
      'viewbox': iloiloViewBox,
      'bounded': '1',
      'zoom': '18',
    });

    final response = await _client.get(
      uri,
      headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw GeocodingException(
        'Reverse lookup failed (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const GeocodingException('Unexpected reverse response');
    }

    final name = decoded['display_name']?.toString();
    if (name == null || name.isEmpty) {
      throw const GeocodingException('No address for this location');
    }

    _evictIfNeeded(_reverseCache, _maxCacheEntries);
    _reverseCache[key] = name;
    return name;
  }

  void _evictIfNeeded<K, V>(Map<K, V> cache, int maxEntries) {
    while (cache.length >= maxEntries) {
      cache.remove(cache.keys.first);
    }
  }
}

class NominatimSearchHit {
  const NominatimSearchHit({
    required this.displayName,
    required this.point,
  });

  final String displayName;
  final LatLng point;
}

class GeocodingException implements Exception {
  const GeocodingException(this.message);
  final String message;

  @override
  String toString() => message;
}
