/// Dashboard API base URL (no trailing slash). Shared by public API clients.
const String apiBaseUrl = 'https://jippy.shinosawa-laboratories.dev'; // Production
// const String apiBaseUrl = 'http://192.168.5.212:6769'; // Local Development

/// Public API URL for all routes and regions (dashboard API shape).
const String routesApiUrl = '$apiBaseUrl/api/public/all';

/// Public API URL for feedback submission.
const String feedbackApiUrl = '$apiBaseUrl/api/public/feedback';

/// Public API URL for step-by-step navigation suggestions.
const String navigateApiUrl = '$apiBaseUrl/api/public/navigate/v2';

/// Nominatim URL
const String nominatimUrl = '$apiBaseUrl/api/public/nominatim';

/// Valhalla proxy status endpoint.
const String valhallaStatusApiUrl =
    '$apiBaseUrl/api/public/osm/valhalla/status';

/// Valhalla route endpoint. Append encoded `json` query parameter when calling.
const String valhallaRouteApiUrl = '$apiBaseUrl/api/public/osm/valhalla/route';

/// Fallback Raster Tile URL.
const String mapRasterFallback =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Default Vector Tile URL.
const String mapVectorTile =
    'https://tileserver.shinosawa-laboratories.dev/styles/liberty/style.json';

const String packageName = 'com.jippy.jippy_mobile';

/// Public endpoint that validates a Play subscription purchase token server-side
/// and returns the canonical entitlement. Only used when server verification is
/// enabled (see `billing_config.dart`); the client-only phase never calls it.
const String subscriptionVerifyApiUrl =
    '$apiBaseUrl/api/public/subscriptions/verify';

/// Resolves a dashboard image path or URL to an absolute URL.
/// Passes through [http/https] URLs; otherwise prefixes [apiBaseUrl].
String resolveApiImageUrl(String pathOrUrl) {
  final trimmed = pathOrUrl.trim();
  if (trimmed.isEmpty) return '';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) {
    return '$apiBaseUrl$trimmed';
  }
  return '$apiBaseUrl/$trimmed';
}
