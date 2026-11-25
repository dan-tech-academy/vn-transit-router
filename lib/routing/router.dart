import '../data/geo.dart';
import '../data/transit_data.dart';
import 'fares.dart';

/// Tunables for the estimate-based router. There are no timetables in the
/// data, so ride times come from distance and waits from headways.
class RouterConfig {
  final double walkSpeed; // m/s
  final double walkDetour; // straight-line to real-path factor
  final double accessRadius;
  final double accessRadiusMax;
  final double transferRadius;
  final int maxRides;
  const RouterConfig({
    this.walkSpeed = 1.2,
    this.walkDetour = 1.3,
    this.accessRadius = 800,
    this.accessRadiusMax = 2500,
    this.transferRadius = 250,
    this.maxRides = 4,
  });

  static double speedOf(TransitMode m) => switch (m) {
    TransitMode.bus => 22 / 3.6,
    TransitMode.metro => 45 / 3.6,
    TransitMode.ferry => 20 / 3.6,
  };

  static int dwellOf(TransitMode m) => switch (m) {
    TransitMode.bus => 20,
    TransitMode.metro => 30,
    TransitMode.ferry => 120,
  };

  static int defaultHeadwayMin(TransitMode m) => switch (m) {
    TransitMode.bus => 15,
    TransitMode.metro => 10,
    TransitMode.ferry => 60,
  };
}

enum LegKind { walk, ride }

class Leg {
  final LegKind kind;
  final int seconds;
  final int metres;
  final List<Geo> path;
  final String fromName;
  final String toName;

  // Ride-only fields.
  final TransitRoute? route;
  final int fromPos;
  final int toPos;
  final int waitSeconds;
  final int fare;

  const Leg.walk({
    required this.seconds,
    required this.metres,
    required this.path,
    required this.fromName,
    required this.toName,
  }) : kind = LegKind.walk,
       route = null,
       fromPos = 0,
       toPos = 0,
       waitSeconds = 0,
       fare = 0;

  const Leg.ride({
    required TransitRoute this.route,
    required this.fromPos,
    required this.toPos,
    required this.seconds,
    required this.waitSeconds,
    required this.metres,
    required this.path,
    required this.fromName,
    required this.toName,
    required this.fare,
  }) : kind = LegKind.ride;

  int get stopCount => toPos - fromPos;
}

class Itinerary {
  final List<Leg> legs;
  Itinerary(this.legs);

  late final int seconds = legs.fold(
    0,
    (a, l) => a + l.seconds + l.waitSeconds,
  );
  late final int walkMetres = legs
      .where((l) => l.kind == LegKind.walk)
      .fold(0, (a, l) => a + l.metres);
  late final int fare = legs.fold(0, (a, l) => a + l.fare);
  late final List<Leg> rides = legs
      .where((l) => l.kind == LegKind.ride)
      .toList();
  int get transfers => rides.isEmpty ? 0 : rides.length - 1;
  bool get walkOnly => rides.isEmpty;
  String get signature => rides.map((l) => l.route!.lineKey).join('>');
}

class TransitRouter {
  final TransitData data;
  final RouterConfig config;
  late final List<List<int>> _cum; // seconds from first stop, per route
  late final List<List<(int, int)>> _footpaths; // stop -> (stop, seconds)

  TransitRouter(this.data, {this.config = const RouterConfig()}) {
    _cum = [
      for (final r in data.routes)
        [
          for (var i = 0; i < r.stops.length; i++)
            (r.dist[i] / RouterConfig.speedOf(r.mode)).round() +
                i * RouterConfig.dwellOf(r.mode),
        ],
    ];
    _footpaths = [
      for (final s in data.stops)
        [
          for (final (o, d) in data.stopsNear(s.geo, config.transferRadius))
            if (o.index != s.index) (o.index, walkSeconds(d)),
        ],
    ];
  }

  int walkSeconds(double straightMetres) =>
      (straightMetres * config.walkDetour / config.walkSpeed).round();

  int waitSeconds(TransitRoute r) =>
      (r.headwayMin ?? RouterConfig.defaultHeadwayMin(r.mode)) * 30;

  /// Returns up to [maxResults] distinct itineraries, best first.
  List<Itinerary> plan(
    Geo origin,
    Geo dest, {
    String originName = 'Điểm đi',
    String destName = 'Điểm đến',
    int maxResults = 5,
  }) {
    final results = <Itinerary>[];
    final seen = <String>{};
    void add(Itinerary? it) {
      if (it == null || !seen.add(it.signature)) return;
      results.add(it);
    }

    final direct = distanceBetween(origin, dest);
    final walk = Itinerary([
      Leg.walk(
        seconds: walkSeconds(direct),
        metres: (direct * config.walkDetour).round(),
        path: [origin, dest],
        fromName: originName,
        toName: destName,
      ),
    ]);

    final access = _access(origin);
    final egress = _access(dest);
    if (access.isNotEmpty && egress.isNotEmpty) {
      final banned = <String>{};
      final first = _raptor(
        origin,
        dest,
        access,
        egress,
        banned,
        originName,
        destName,
      );
      first.forEach(add);
      // Alternatives: forbid each line of the best plan in turn.
      if (first.isNotEmpty) {
        for (final leg in first.first.rides) {
          if (results.length >= maxResults + 2) break;
          _raptor(
            origin,
            dest,
            access,
            egress,
            {leg.route!.lineKey},
            originName,
            destName,
          ).forEach(add);
        }
      }
    }
    results.removeWhere((it) => it.seconds > walk.seconds && direct < 5000);
    results.sort((a, b) => _score(a).compareTo(_score(b)));
    final out = results.take(maxResults).toList();
    if (direct <= 3000 || out.isEmpty) {
      out.add(walk);
      out.sort((a, b) => _score(a).compareTo(_score(b)));
    }
    return out;
  }

  // Generalised cost: time plus penalties for transfers and long walks.
  int _score(Itinerary it) =>
      it.seconds + it.transfers * 300 + (it.walkMetres * 0.3).round();

  List<(Stop, double)> _access(Geo p) {
    var near = data.stopsNear(p, config.accessRadius, limit: 60);
    if (near.length < 3) {
      near = data.stopsNear(p, config.accessRadiusMax, limit: 12);
    }
    return near;
  }

  static const int _inf = 1 << 40;

  List<Itinerary> _raptor(
    Geo origin,
    Geo dest,
    List<(Stop, double)> access,
    List<(Stop, double)> egress,
    Set<String> banned,
    String originName,
    String destName,
  ) {
    final n = data.stops.length;
    final rounds = config.maxRides;
    // tau[k][s]: earliest arrival at s using at most k rides.
    final tau = List.generate(rounds + 1, (_) => List.filled(n, _inf));
    // Parent pointers: ride (route, boardPos, alightPos) or walk (fromStop).
    final pRoute = List.generate(rounds + 1, (_) => List.filled(n, -1));
    final pBoard = List.generate(rounds + 1, (_) => List.filled(n, -1));
    final pAlight = List.generate(rounds + 1, (_) => List.filled(n, -1));
    final pWalkFrom = List.generate(rounds + 1, (_) => List.filled(n, -1));

    var marked = <int>{};
    for (final (s, d) in access) {
      tau[0][s.index] = walkSeconds(d);
      marked.add(s.index);
    }
    final egressTime = {for (final (s, d) in egress) s.index: walkSeconds(d)};

    for (var k = 1; k <= rounds && marked.isNotEmpty; k++) {
      final cur = tau[k];
      final prev = tau[k - 1];
      for (var s = 0; s < n; s++) {
        cur[s] = prev[s];
      }
      final routesToScan = <int>{};
      for (final s in marked) {
        routesToScan.addAll(data.stops[s].routes);
      }
      final next = <int>{};
      for (final ri in routesToScan) {
        final r = data.routes[ri];
        if (banned.contains(r.lineKey)) continue;
        final cum = _cum[ri];
        final wait = waitSeconds(r);
        var bestOffset = _inf;
        var boardPos = -1;
        for (var i = 0; i < r.stops.length; i++) {
          final s = r.stops[i];
          if (boardPos >= 0) {
            final arr = bestOffset + cum[i];
            if (arr < cur[s]) {
              cur[s] = arr;
              pRoute[k][s] = ri;
              pBoard[k][s] = boardPos;
              pAlight[k][s] = i;
              pWalkFrom[k][s] = -1;
              next.add(s);
            }
          }
          if (prev[s] < _inf) {
            final off = prev[s] + wait - cum[i];
            if (off < bestOffset) {
              bestOffset = off;
              boardPos = i;
            }
          }
        }
      }
      // Foot transfers from stops improved by a ride in this round.
      for (final s in next.toList()) {
        if (pRoute[k][s] < 0) continue;
        for (final (o, sec) in _footpaths[s]) {
          final arr = cur[s] + sec;
          if (arr < cur[o]) {
            cur[o] = arr;
            pRoute[k][o] = -1;
            pWalkFrom[k][o] = s;
            next.add(o);
          }
        }
      }
      marked = next;
    }

    final out = <Itinerary>[];
    var bestSoFar = _inf;
    for (var k = 1; k <= rounds; k++) {
      var best = _inf;
      var bestStop = -1;
      egressTime.forEach((s, sec) {
        if (tau[k][s] < _inf && tau[k][s] + sec < best) {
          best = tau[k][s] + sec;
          bestStop = s;
        }
      });
      // Keep only Pareto-better options: more rides must buy real time.
      if (bestStop < 0 || best >= bestSoFar - 120) continue;
      bestSoFar = best;
      final it = _build(
        k,
        bestStop,
        origin,
        dest,
        tau,
        pRoute,
        pBoard,
        pAlight,
        pWalkFrom,
        originName,
        destName,
      );
      if (it != null) out.add(it);
    }
    return out;
  }

  Itinerary? _build(
    int k,
    int endStop,
    Geo origin,
    Geo dest,
    List<List<int>> tau,
    List<List<int>> pRoute,
    List<List<int>> pBoard,
    List<List<int>> pAlight,
    List<List<int>> pWalkFrom,
    String originName,
    String destName,
  ) {
    final legs = <Leg>[];
    var s = endStop;
    var round = k;
    var guard = 0;
    while (round > 0 && guard++ < 64) {
      // Step down to the round where this arrival was actually produced.
      while (round > 0 && tau[round][s] == tau[round - 1][s]) {
        round--;
      }
      if (round == 0) break;
      final walkFrom = pWalkFrom[round][s];
      if (pRoute[round][s] < 0) {
        if (walkFrom < 0) return null;
        final a = data.stops[walkFrom], b = data.stops[s];
        final d = distanceBetween(a.geo, b.geo);
        legs.add(
          Leg.walk(
            seconds: walkSeconds(d),
            metres: (d * config.walkDetour).round(),
            path: [a.geo, b.geo],
            fromName: a.displayName,
            toName: b.displayName,
          ),
        );
        s = walkFrom;
        continue;
      }
      final r = data.routes[pRoute[round][s]];
      final bp = pBoard[round][s], ap = pAlight[round][s];
      final cum = _cum[r.index];
      final metres = r.dist[ap] - r.dist[bp];
      legs.add(
        Leg.ride(
          route: r,
          fromPos: bp,
          toPos: ap,
          seconds: cum[ap] - cum[bp],
          waitSeconds: waitSeconds(r),
          metres: metres,
          path: r.shapeBetween(bp, ap),
          fromName: data.stops[r.stops[bp]].displayName,
          toName: data.stops[r.stops[ap]].displayName,
          fare: estimateFare(r, metres),
        ),
      );
      s = r.stops[bp];
      round--;
    }
    final first = data.stops[s];
    final last = data.stops[endStop];
    final dA = distanceBetween(origin, first.geo);
    final dE = distanceBetween(last.geo, dest);
    final ordered = <Leg>[
      Leg.walk(
        seconds: walkSeconds(dA),
        metres: (dA * config.walkDetour).round(),
        path: [origin, first.geo],
        fromName: originName,
        toName: first.displayName,
      ),
      ...legs.reversed,
      Leg.walk(
        seconds: walkSeconds(dE),
        metres: (dE * config.walkDetour).round(),
        path: [last.geo, dest],
        fromName: last.displayName,
        toName: destName,
      ),
    ];
    final merged = <Leg>[];
    for (final l in ordered) {
      if (l.kind == LegKind.walk && l.metres < 15) continue;
      if (l.kind == LegKind.walk &&
          merged.isNotEmpty &&
          merged.last.kind == LegKind.walk) {
        final p = merged.removeLast();
        merged.add(
          Leg.walk(
            seconds: p.seconds + l.seconds,
            metres: p.metres + l.metres,
            path: [...p.path, ...l.path],
            fromName: p.fromName,
            toName: l.toName,
          ),
        );
      } else {
        merged.add(l);
      }
    }
    return Itinerary(merged);
  }
}
