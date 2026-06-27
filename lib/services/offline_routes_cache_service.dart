import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/config/api_config.dart';
import '../models/jeepney_route.dart';
import '../models/routes_and_stations_data.dart';

const Duration _routesDownloadTimeout = Duration(seconds: 30);
const String _routesFileName = 'routes_api.json';
const String _manifestFileName = 'image_manifest.json';
const String _imagesDirName = 'images';

/// Persists routes, regions, and sticker images from `/api/public/all` for offline use.
///
/// API [imageUrls] are relative paths such as `/api/public/images/{uuid}.png`
/// (see `.ctx-clues/data.json`). The manifest indexes each file by raw path,
/// resolved URL, URI path, and filename so offline lookup succeeds after parsing.
class OfflineRoutesCacheService {
  OfflineRoutesCacheService._();

  static final OfflineRoutesCacheService instance = OfflineRoutesCacheService._();

  Directory? _cacheRoot;

  Future<Directory> _ensureCacheRoot() async {
    if (_cacheRoot != null) return _cacheRoot!;
    final docs = await getApplicationDocumentsDirectory();
    _cacheRoot = Directory('${docs.path}/offline_routes');
    if (!_cacheRoot!.existsSync()) {
      await _cacheRoot!.create(recursive: true);
    }
    return _cacheRoot!;
  }

  Future<File> _routesFile() async {
    final root = await _ensureCacheRoot();
    return File('${root.path}/$_routesFileName');
  }

  Future<File> _manifestFile() async {
    final root = await _ensureCacheRoot();
    return File('${root.path}/$_manifestFileName');
  }

  Future<Directory> _imagesDir() async {
    final root = await _ensureCacheRoot();
    final dir = Directory('${root.path}/$_imagesDirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> hasCachedData() async {
    final file = await _routesFile();
    return file.existsSync();
  }

  Future<RoutesAndStationsData?> loadCached() async {
    try {
      final file = await _routesFile();
      if (!file.existsSync()) return null;

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final data = RoutesAndStationsData.fromJson(json);
      final manifest = await _readManifest();
      return _applyLocalImagePaths(data, manifest);
    } catch (_) {
      return null;
    }
  }

  /// Downloads API payload and all referenced images. Reports progress in [0, 1].
  Future<void> downloadAndCache({
    required void Function(double progress, int imagesDone, int imagesTotal)
    onProgress,
  }) async {
    final response = await http
        .get(Uri.parse(routesApiUrl))
        .timeout(_routesDownloadTimeout);

    if (response.statusCode != 200) {
      throw Exception('Routes API returned ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw Exception('Routes API returned invalid JSON');
    }

    final routesFile = await _routesFile();
    await routesFile.writeAsString(response.body);

    final rawImagePaths = _collectRawImagePaths(json);
    final imagesDir = await _imagesDir();
    final manifest = <String, String>{};
    final total = rawImagePaths.length;

    onProgress(0, 0, total);

    for (var i = 0; i < rawImagePaths.length; i++) {
      final rawPath = rawImagePaths[i];
      final downloadUrl = resolveApiImageUrl(rawPath);
      if (downloadUrl.isEmpty) continue;

      final localPath = await _downloadImage(
        downloadUrl: downloadUrl,
        rawPath: rawPath,
        imagesDir: imagesDir,
      );
      if (localPath != null) {
        _registerManifestKeys(manifest, rawPath: rawPath, localPath: localPath);
      }

      final progress = total == 0 ? 1.0 : (i + 1) / total;
      onProgress(progress, i + 1, total);
    }

    await _writeManifest(manifest);
    onProgress(1, total, total);
  }

  Future<void> deleteCache() async {
    _cacheRoot = null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/offline_routes');
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best effort cleanup.
    }
  }

  List<String> _collectRawImagePaths(Map<String, dynamic> json) {
    final paths = <String>{};
    _walkJsonForRawImagePaths(json, paths);
    return paths.toList(growable: false);
  }

  void _walkJsonForRawImagePaths(dynamic node, Set<String> paths) {
    if (node is Map<String, dynamic>) {
      for (final entry in node.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key == 'imageUrls' && value is List) {
          for (final item in value) {
            final raw = item?.toString().trim() ?? '';
            if (raw.isNotEmpty) paths.add(raw);
          }
        } else if (key == 'imageUrl' ||
            key == 'image' ||
            key == 'thumbnailUrl') {
          final raw = value?.toString().trim() ?? '';
          if (raw.isNotEmpty) paths.add(raw);
        } else {
          _walkJsonForRawImagePaths(value, paths);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        _walkJsonForRawImagePaths(item, paths);
      }
    }
  }

  void _registerManifestKeys(
    Map<String, String> manifest, {
    required String rawPath,
    required String localPath,
  }) {
    manifest[rawPath] = localPath;

    final resolved = resolveApiImageUrl(rawPath);
    if (resolved.isNotEmpty) {
      manifest[resolved] = localPath;
    }

    for (final key in _manifestLookupKeys(rawPath)) {
      manifest[key] = localPath;
    }
    if (resolved.isNotEmpty) {
      for (final key in _manifestLookupKeys(resolved)) {
        manifest[key] = localPath;
      }
    }
  }

  Iterable<String> _manifestLookupKeys(String urlOrPath) sync* {
    if (urlOrPath.isEmpty) return;

    yield urlOrPath;

    final resolved = resolveApiImageUrl(urlOrPath);
    if (resolved.isNotEmpty && resolved != urlOrPath) {
      yield resolved;
    }

    try {
      yield Uri.parse(urlOrPath).path;
      if (resolved.isNotEmpty) {
        yield Uri.parse(resolved).path;
      }
    } catch (_) {
      // Ignore malformed URIs.
    }

    final fileName = urlOrPath.split('/').where((s) => s.isNotEmpty).lastOrNull;
    if (fileName != null && fileName.isNotEmpty) {
      yield fileName;
    }
  }

  Future<String?> _downloadImage({
    required String downloadUrl,
    required String rawPath,
    required Directory imagesDir,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(downloadUrl))
          .timeout(_routesDownloadTimeout);
      if (response.statusCode != 200) return null;

      final extension = _extensionForUrl(downloadUrl, response.headers['content-type']);
      final fileName = _fileNameForImage(rawPath, downloadUrl, extension);
      final file = File('${imagesDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  String _fileNameForImage(String rawPath, String downloadUrl, String extension) {
    final fromRaw = rawPath.split('/').where((s) => s.isNotEmpty).lastOrNull;
    if (fromRaw != null && fromRaw.contains('.')) return fromRaw;

    try {
      final fromUrl = Uri.parse(downloadUrl).pathSegments.lastOrNull;
      if (fromUrl != null && fromUrl.contains('.')) return fromUrl;
    } catch (_) {
      // Fall through.
    }

    return '${downloadUrl.hashCode.abs()}$extension';
  }

  String _extensionForUrl(String url, String? contentType) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.gif')) return '.gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return '.jpg';

    final type = contentType?.toLowerCase() ?? '';
    if (type.contains('png')) return '.png';
    if (type.contains('webp')) return '.webp';
    if (type.contains('gif')) return '.gif';
    return '.jpg';
  }

  Future<Map<String, String>> _readManifest() async {
    try {
      final file = await _manifestFile();
      if (!file.existsSync()) return const {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return const {};
      return json.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return const {};
    }
  }

  Future<void> _writeManifest(Map<String, String> manifest) async {
    final file = await _manifestFile();
    await file.writeAsString(jsonEncode(manifest));
  }

  RoutesAndStationsData _applyLocalImagePaths(
    RoutesAndStationsData data,
    Map<String, String> manifest,
  ) {
    if (manifest.isEmpty) return data;

    final routes = data.routes
        .map((route) => _routeWithLocalImages(route, manifest))
        .toList(growable: false);

    return RoutesAndStationsData(
      routes: routes,
      stations: data.stations,
      regions: data.regions,
      closures: data.closures,
    );
  }

  JeepneyRoute _routeWithLocalImages(
    JeepneyRoute route,
    Map<String, String> manifest,
  ) {
    if (route.imageUrls.isEmpty) return route;

    final localUrls = route.imageUrls
        .map((url) => _resolveOfflineImagePath(url, manifest))
        .toList(growable: false);

    return JeepneyRoute(
      id: route.id,
      routeNumber: route.routeNumber,
      routeName: route.routeName,
      routeColor: route.routeColor,
      routeDetails: route.routeDetails,
      goingTo: route.goingTo,
      goingBack: route.goingBack,
      polylineGoingTo: route.polylineGoingTo,
      polylineGoingBack: route.polylineGoingBack,
      imageUrls: localUrls,
    );
  }

  String _resolveOfflineImagePath(String url, Map<String, String> manifest) {
    for (final key in _manifestLookupKeys(url)) {
      final local = manifest[key];
      if (local != null && local.isNotEmpty) {
        return local;
      }
    }
    return url;
  }
}
