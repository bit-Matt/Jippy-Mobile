import 'package:latlong2/latlong.dart';

/// Shared map configuration for MapLibre basemaps and defaults.
class MapConfig {
  MapConfig._();

  static const String userAgent =
      'JippyMobile/1.0 (https://jippy.shinosawa-laboratories.dev)';

  /// Vector style for routes and tricycles screens.
  static const String routesStyleUrl =
      'https://tileserver.shinosawa-laboratories.dev/styles/liberty/style.json';

  /// Vector style for the Go screen.
  static const String goStyleUrl =
      'https://tileserver.shinosawa-laboratories.dev/styles/liberty/style.json';

  /// Bundled OSM raster fallback when remote vector styles are unavailable.
  static const String osmRasterStyleAsset = 'assets/map/osm_raster_style.json';

  /// Default center: Iloilo City, Philippines.
  static final LatLng iloiloCenter = LatLng(10.7202, 122.5621);

  /// Routes / tricycles default center (slightly north-west of city core).
  static final LatLng routesDefaultCenter = LatLng(10.7, 122.5521);

  /// Offline vector tile pack for Iloilo City.
  static const double iloiloOfflineMinZoom = 10;
  static const double iloiloOfflineMaxZoom = 16;
  static const LatLng iloiloOfflineSouthWest = LatLng(10.636251, 122.379863);
  static const LatLng iloiloOfflineNorthEast = LatLng(10.835500, 122.610123);
  static const String iloiloOfflineRegionKey = 'iloilo_city';
}
