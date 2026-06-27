import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';

const Duration _serverProbeTimeout = Duration(seconds: 6);

bool hasNetworkInterface(List<ConnectivityResult> results) {
  if (results.length == 1 && results.single == ConnectivityResult.none) {
    return false;
  }
  return true;
}

/// Shared online/offline state for the app shell and map screens.
///
/// [isOnline] is true only when the device has a network interface **and** the
/// Jippy API server responds successfully at startup and on connectivity changes.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(false);

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _initialized = false;
  bool _refreshInFlight = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await refreshOnlineStatus();

    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(refreshOnlineStatus());
    });
  }

  /// Re-evaluates network interface + server reachability.
  Future<void> refreshOnlineStatus() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final interfaceResults = await _connectivity.checkConnectivity();
      if (!hasNetworkInterface(interfaceResults)) {
        _setOnline(false);
        return;
      }

      final serverReachable = await _isServerReachable();
      _setOnline(serverReachable);
    } finally {
      _refreshInFlight = false;
    }
  }

  void _setOnline(bool online) {
    if (isOnline.value == online) return;
    isOnline.value = online;
  }

  Future<bool> _isServerReachable() async {
    try {
      final response = await http
          .get(Uri.parse(routesApiUrl))
          .timeout(_serverProbeTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    isOnline.dispose();
  }
}
