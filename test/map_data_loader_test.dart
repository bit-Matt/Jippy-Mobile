import 'package:flutter_test/flutter_test.dart';
import 'package:jippy_mobile/data/map_data_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadMapData offline', () {
    test('returns empty data when offline without premium', () async {
      final result = await loadMapData(
        online: false,
        premiumUnlocked: false,
      );

      expect(result.data, emptyMapData);
      expect(result.data.routes, isEmpty);
      expect(result.data.regions, isEmpty);
      expect(result.data.stations, isEmpty);
    });

    test('returns empty data when offline with premium but no cache', () async {
      final result = await loadMapData(
        online: false,
        premiumUnlocked: true,
      );

      expect(result.data, emptyMapData);
      expect(result.data.routes, isEmpty);
      expect(result.data.regions, isEmpty);
      expect(result.data.stations, isEmpty);
    });
  });
}
