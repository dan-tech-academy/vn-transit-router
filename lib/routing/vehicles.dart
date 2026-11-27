import 'dart:math' as math;

import '../data/geo.dart';
import '../data/transit_data.dart';
import 'router.dart';

/// Where a vehicle would be if it left on schedule and kept the router's
/// average speed. Not a measured position.
class VehicleEstimate {
  final Geo position;

  /// Position in the route's stop list of the stop it reaches next.
  final int nextStop;
  final int secondsToNext;
  const VehicleEstimate(this.position, this.nextStop, this.secondsToNext);
}

int _vnSeconds(DateTime t) {
  final vn = t.toUtc().add(const Duration(hours: 7));
  return vn.hour * 3600 + vn.minute * 60 + vn.second;
}

/// Vehicles under way on [r] at [t], first departed last. Null when the data
/// has no schedule for the route (no headway with hours, no departures).
List<VehicleEstimate>? estimateVehicles(TransitRoute r, DateTime t) {
  if (r.scheduleOn(t) == null || r.stops.length < 2) return null;
  final times = stopSeconds(r);
  final speed = RouterConfig.speedOf(r.mode);
  final now = _vnSeconds(t);
  final out = <VehicleEstimate>[];
  for (final day in const [0, -1]) {
    final departures = r.scheduleOn(t.add(Duration(days: day))) ?? const [];
    for (final m in departures.reversed) {
      final e = now - (day * 86400 + m * 60);
      if (e < 0 || e >= times.last) continue;
      var i = 0;
      while (e >= times[i + 1]) {
        i++;
      }
      final span = r.dist[i + 1] - r.dist[i];
      final ride = span / speed;
      final f = ride <= 0 ? 1.0 : math.min(1.0, (e - times[i]) / ride);
      out.add(
        VehicleEstimate(
          _along(r.shapeBetween(i, i + 1), f),
          i + 1,
          math.max(0, (ride - (e - times[i])).round()),
        ),
      );
    }
  }
  return out;
}

/// Minutes after Vietnam midnight of the next departure from the first stop
/// before the end of the day of [t], or null. Counts what is left of hours
/// that began the day before and run past midnight.
int? nextDeparture(TransitRoute r, DateTime t) {
  final now = _vnSeconds(t);
  for (final day in const [-1, 0]) {
    final departures = r.scheduleOn(t.add(Duration(days: day)));
    for (final m in departures ?? const <int>[]) {
      if (day * 86400 + m * 60 > now) return m % 1440;
    }
  }
  return null;
}

Geo _along(List<Geo> path, double f) {
  if (path.length < 2 || f <= 0) return path.first;
  final lengths = [
    for (var i = 1; i < path.length; i++) distanceBetween(path[i - 1], path[i]),
  ];
  var left = lengths.fold(0.0, (a, b) => a + b) * f;
  for (var i = 0; i < lengths.length; i++) {
    if (left <= lengths[i] && lengths[i] > 0) {
      final k = left / lengths[i];
      return Geo(
        path[i].lat + (path[i + 1].lat - path[i].lat) * k,
        path[i].lon + (path[i + 1].lon - path[i].lon) * k,
      );
    }
    left -= lengths[i];
  }
  return path.last;
}
