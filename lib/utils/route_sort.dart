import 'package:collection/collection.dart';

import '../models/jeepney_route.dart';

int compareRouteNumbersAsc(JeepneyRoute a, JeepneyRoute b) {
  final aRaw = a.routeNumber.trim();
  final bRaw = b.routeNumber.trim();
  return compareNatural(aRaw, bRaw);
}
