/// Dashboard API base URL (no trailing slash). Shared by public API clients.
// const String apiBaseUrl = 'https://jippy.shinosawa-laboratories.dev'; // Production
const String apiBaseUrl = 'http://192.168.175.1:6769'; // Local Development

/// Public API URL for all routes and regions (dashboard API shape).
const String routesApiUrl = '$apiBaseUrl/api/public/all';

/// Public API URL for feedback submission.
const String feedbackApiUrl = '$apiBaseUrl/api/public/feedback';

/// Valhalla proxy status endpoint.
const String valhallaStatusApiUrl =
    '$apiBaseUrl/api/public/osm/valhalla/status';

/// Valhalla route endpoint. Append encoded `json` query parameter when calling.
const String valhallaRouteApiUrl = '$apiBaseUrl/api/public/osm/valhalla/route';
