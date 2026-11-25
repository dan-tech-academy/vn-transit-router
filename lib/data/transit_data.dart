import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'geo.dart';

enum TransitMode { bus, metro, ferry }

class Stop {
  final int index;
  final double lat;
  final double lon;
  final String name;
  final List<int> routes = [];
  Stop(this.index, this.lat, this.lon, this.name);

  Geo get geo => Geo(lat, lon);
  String get displayName => name.isEmpty ? 'Trạm dừng' : name;
}

/// One direction of a line, as mapped in OpenStreetMap.
class TransitRoute {
  final int index;
  final int osmId;
  final String ref;
  final String name;
  final String from;
  final String to;
  final TransitMode mode;
  final String network;
  final String operator;
  final String city;
  final String colour;
  final int? headwayMin;
  final String openingHours;
  final String charge;

  /// Where hours/headway/fare came from when not from OpenStreetMap.
  final String scheduleSource;
  final List<int> stops;

  /// Metres along the shape from the first stop, per stop.
  final List<int> dist;

  /// Index into [shape] for each stop.
  final List<int> shapeIdx;
  final String encodedShape;
  List<Geo>? _shape;

  TransitRoute({
    required this.index,
    required this.osmId,
    required this.ref,
    required this.name,
    required this.from,
    required this.to,
    required this.mode,
    required this.network,
    required this.operator,
    required this.city,
    required this.colour,
    required this.headwayMin,
    required this.openingHours,
    required this.charge,
    required this.scheduleSource,
    required this.stops,
    required this.dist,
    required this.shapeIdx,
    required this.encodedShape,
  });

  List<Geo> get shape => _shape ??= decodePolyline(encodedShape);

  List<Geo> shapeBetween(int fromPos, int toPos) =>
      shape.sublist(shapeIdx[fromPos], shapeIdx[toPos] + 1);

  /// Directions of one line share a key. Network is left out: OSM often tags
  /// it on only one direction. Unnumbered lines pair up by their endpoints.
  String get lineKey {
    var id = ref;
    if (id.isEmpty) {
      final ends = [from, to]..sort();
      id = from.isEmpty || to.isEmpty ? name : ends.join('~');
    }
    return '$city|${mode.name}|$id';
  }

  static const _days = ['mo', 'tu', 'we', 'th', 'fr', 'sa', 'su'];
  static final _dayRe = RegExp(
    r'\b(mo|tu|we|th|fr|sa|su)\b(?:\s*-\s*(mo|tu|we|th|fr|sa|su)\b)?',
  );
  static final _rangeRe = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})');

  /// Whether the mapped `opening_hours` cover [t], read in Vietnam time
  /// (UTC+7). Hours that are missing or not plain day/time ranges count as
  /// in service. A range past midnight belongs to the day it starts on.
  bool inServiceAt(DateTime t) {
    if (openingHours.trim().isEmpty) return true;
    final vn = t.toUtc().add(const Duration(hours: 7));
    final today = vn.weekday - 1, yesterday = (today + 6) % 7;
    final now = vn.hour * 60 + vn.minute;
    for (final rule in openingHours.toLowerCase().split(';')) {
      final ranges = _rangeRe.allMatches(rule).toList();
      if (ranges.isEmpty) return true;
      final dayMatches = _dayRe.allMatches(rule).toList();
      final days = <int>{};
      for (final m in dayMatches) {
        final a = _days.indexOf(m[1]!);
        final b = m[2] == null ? a : _days.indexOf(m[2]!);
        for (var d = a; ; d = (d + 1) % 7) {
          days.add(d);
          if (d == b) break;
        }
      }
      if (dayMatches.isEmpty) days.addAll([0, 1, 2, 3, 4, 5, 6]);
      for (final m in ranges) {
        final open = int.parse(m[1]!) * 60 + int.parse(m[2]!);
        var close = int.parse(m[3]!) * 60 + int.parse(m[4]!);
        if (close <= open) close += 1440;
        if (days.contains(today) && now >= open && now <= close) return true;
        if (days.contains(yesterday) && now + 1440 <= close) return true;
      }
    }
    return false;
  }

  String get label {
    if (ref.isNotEmpty) return ref;
    return mode == TransitMode.metro ? 'Metro' : '?';
  }

  String get modeLabel => switch (mode) {
    TransitMode.bus => 'Xe buýt',
    TransitMode.metro => 'Metro',
    TransitMode.ferry => 'Buýt sông',
  };

  String get title {
    if (from.isNotEmpty && to.isNotEmpty) return '$from → $to';
    return name.isEmpty ? '$modeLabel $label' : name;
  }
}

class TransitData {
  final String generated;
  final List<Stop> stops;
  final List<TransitRoute> routes;
  late final _Grid _grid = _Grid(stops);

  TransitData(this.generated, this.stops, this.routes);

  static TransitData fromGzip(Uint8List bytes) =>
      fromJson(utf8.decode(gzip.decode(bytes)));

  static TransitData fromJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final rawStops = j['stops'] as List;
    final stops = <Stop>[
      for (var i = 0; i < rawStops.length; i++)
        Stop(
          i,
          (rawStops[i][0] as num).toDouble(),
          (rawStops[i][1] as num).toDouble(),
          rawStops[i][2] as String,
        ),
    ];
    final rawRoutes = j['routes'] as List;
    final routes = <TransitRoute>[];
    for (var i = 0; i < rawRoutes.length; i++) {
      final r = rawRoutes[i] as Map<String, dynamic>;
      final route = TransitRoute(
        index: i,
        osmId: r['id'] as int,
        ref: r['ref'] as String,
        name: r['name'] as String,
        from: r['from'] as String,
        to: r['to'] as String,
        mode: TransitMode.values.byName(r['mode'] as String),
        network: r['net'] as String,
        operator: r['op'] as String,
        city: r['city'] as String,
        colour: r['col'] as String,
        headwayMin: ((r['hw'] as int?) ?? 0) > 0 ? r['hw'] as int : null,
        openingHours: r['oh'] as String,
        charge: r['charge'] as String,
        scheduleSource: r['sched'] as String? ?? '',
        stops: (r['stops'] as List).cast<int>(),
        dist: (r['dist'] as List).cast<int>(),
        shapeIdx: (r['idx'] as List).cast<int>(),
        encodedShape: r['shape'] as String,
      );
      routes.add(route);
      for (final s in route.stops) {
        final list = stops[s].routes;
        if (list.isEmpty || list.last != i) list.add(i);
      }
    }
    return TransitData(j['generated'] as String? ?? '', stops, routes);
  }

  /// Stops within [radius] metres, nearest first.
  List<(Stop, double)> stopsNear(Geo p, double radius, {int? limit}) {
    final out = _grid.near(p, radius);
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return limit != null && out.length > limit ? out.sublist(0, limit) : out;
  }

  List<Stop> stopsInBounds(
    double south,
    double west,
    double north,
    double east, {
    int limit = 300,
  }) => _grid.inBounds(south, west, north, east, limit);
}

class _Grid {
  static const double cell = 0.005; // about 550 m
  final List<Stop> stops;
  final Map<int, List<int>> cells = {};

  _Grid(this.stops) {
    for (final s in stops) {
      (cells[_key(_c(s.lat), _c(s.lon))] ??= []).add(s.index);
    }
  }

  static int _c(double v) => (v / cell).floor();
  static int _key(int a, int b) => a * 100000 + b;

  List<(Stop, double)> near(Geo p, double radius) {
    final out = <(Stop, double)>[];
    final dLat = radius / 111320;
    final dLon = radius / (111320 * cos(p.lat * pi / 180));
    for (var a = _c(p.lat - dLat); a <= _c(p.lat + dLat); a++) {
      for (var b = _c(p.lon - dLon); b <= _c(p.lon + dLon); b++) {
        for (final i in cells[_key(a, b)] ?? const <int>[]) {
          final s = stops[i];
          final d = haversine(p.lat, p.lon, s.lat, s.lon);
          if (d <= radius) out.add((s, d));
        }
      }
    }
    return out;
  }

  List<Stop> inBounds(
    double south,
    double west,
    double north,
    double east,
    int limit,
  ) {
    final out = <Stop>[];
    for (var a = _c(south); a <= _c(north); a++) {
      for (var b = _c(west); b <= _c(east); b++) {
        for (final i in cells[_key(a, b)] ?? const <int>[]) {
          final s = stops[i];
          if (s.lat >= south &&
              s.lat <= north &&
              s.lon >= west &&
              s.lon <= east) {
            out.add(s);
            if (out.length >= limit) return out;
          }
        }
      }
    }
    return out;
  }
}
