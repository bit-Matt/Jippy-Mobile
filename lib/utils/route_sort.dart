import '../models/jeepney_route.dart';

int compareRouteNumbersAsc(JeepneyRoute a, JeepneyRoute b) {
  final aRaw = a.routeNumber.trim();
  final bRaw = b.routeNumber.trim();

  final aKey = routeNumberSortKey(aRaw);
  final bKey = routeNumberSortKey(bRaw);

  // Primary: numeric prefix when present.
  if (aKey.number != null && bKey.number != null) {
    final n = aKey.number!.compareTo(bKey.number!);
    if (n != 0) return n;
  } else if (aKey.number != null && bKey.number == null) {
    return -1; // numeric route numbers come first
  } else if (aKey.number == null && bKey.number != null) {
    return 1;
  }

  // Secondary: suffix (e.g. 2A after 2).
  final s = aKey.suffix.compareTo(bKey.suffix);
  if (s != 0) return s;

  // Tertiary: full string compare (stable/consistent).
  return aKey.full.compareTo(bKey.full);
}

({int? number, String suffix, String full}) routeNumberSortKey(String raw) {
  final lower = raw.toLowerCase();
  final match = RegExp(r'^\s*(\d+)').firstMatch(lower);
  final int? number = match != null ? int.tryParse(match.group(1)!) : null;
  final suffix = match != null ? lower.substring(match.end).trim() : lower;
  return (number: number, suffix: suffix, full: lower);
}
