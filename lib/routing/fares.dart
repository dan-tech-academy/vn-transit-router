import '../data/transit_data.dart';

/// Rough single-ride fare in VND. Uses the fare mapped on the route when there
/// is one, otherwise a per-city guess; the UI always labels fares "ước tính".
int estimateFare(TransitRoute r, int rideMetres) {
  final mapped = RegExp(r'^(\d{4,6})\s*VND$').firstMatch(r.charge.trim());
  if (mapped != null) return int.parse(mapped.group(1)!);
  final km = rideMetres / 1000;
  final routeKm = r.dist.last / 1000;
  switch (r.mode) {
    case TransitMode.metro:
      if (r.city == 'TP. Hồ Chí Minh') return _linear(km, 7000, 20000, 19.7);
      return _linear(km, 8000, 15000, 13);
    case TransitMode.ferry:
      return 15000;
    case TransitMode.bus:
      if (r.city == 'Hà Nội') {
        if (routeKm < 15) return 8000;
        if (routeKm < 25) return 10000;
        return 12000;
      }
      if (r.city == 'TP. Hồ Chí Minh') return routeKm < 18 ? 6000 : 7000;
      return 7000;
  }
}

int _linear(double km, int min, int max, double fullKm) {
  final v = min + (max - min) * (km / fullKm).clamp(0, 1);
  return (v / 1000).round() * 1000;
}
