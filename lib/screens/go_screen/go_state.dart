/// Whether the user is placing the origin or destination on the routes map.
enum GoPinTarget { origin, destination }

/// Top search surface: single-line destination prompt vs two-row editor.
enum GoSearchBarMode { collapsed, expanded }

/// Main Go flow states used to keep map/search/sheet transitions consistent.
enum GoNavigationFlow {
  explore,
  locationDetail,
  routingInput,
  routeSelection,
  routeDetails,
  navigating,
}

/// Active input field in the routing header.
enum GoRoutingField { start, end }

/// Camera style while actively navigating a selected route.
enum GoNavigationMapView {
  /// Tilted, direction-facing perspective (Google Maps–style navigation).
  perspective3d,

  /// North-up top-down view.
  topDown2d,
}
