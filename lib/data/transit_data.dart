import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../l10n.dart';
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
  String get displayName => name.isEmpty ? tr('Trạm dừng', 'Stop') : name;
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

  /// What [scheduleSource] supplied, e.g. "giờ chạy, giãn cách".
  final String scheduleFields;
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
    this.scheduleFields = '',
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
  static final _timeRe = RegExp(r'(\d{1,2}):(\d{2})');
  static final _rangeRe = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})');

  /// Whether the mapped `opening_hours` cover [t], read in Vietnam time
  /// (UTC+7). Missing or unreadable hours count as in service. A range past
  /// midnight belongs to the day it starts on; a lone departure time is
  /// usable for the half hour before it. [wait] is the expected wait before
  /// boarding, which must still fall inside a range.
  bool inServiceAt(DateTime t, {Duration wait = Duration.zero}) {
    if (openingHours.trim().isEmpty) return true;
    final vn = t.toUtc().add(const Duration(hours: 7));
    final today = vn.weekday - 1, yesterday = (today + 6) % 7;
    final now = vn.hour * 60 + vn.minute + vn.second / 60;
    for (final rule in openingHours.toLowerCase().split(';')) {
      final ranges = [
        for (final m in _rangeRe.allMatches(rule))
          (
            int.parse(m[1]!) * 60 + int.parse(m[2]!),
            int.parse(m[3]!) * 60 + int.parse(m[4]!),
            wait.inSeconds / 60,
          ),
        for (final m in _timeRe.allMatches(rule.replaceAll(_rangeRe, '')))
          (
            int.parse(m[1]!) * 60 + int.parse(m[2]!) - 30,
            int.parse(m[1]!) * 60 + int.parse(m[2]!),
            0.0,
          ),
      ];
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
      for (var (open, close, w) in ranges) {
        if (close <= open) close += 1440;
        if (days.contains(today) && now >= open && now + w <= close) {
          return true;
        }
        if (days.contains(yesterday) && now + 1440 + w <= close) return true;
      }
    }
    return false;
  }

  /// Departure times from the first stop on the Vietnam-time day of [t], in
  /// minutes after midnight, when the mapped hours are single departures
  /// (e.g. "Mo-Fr 07:00,17:15") rather than ranges. Null otherwise.
  List<int>? departuresOn(DateTime t) {
    final text = openingHours.toLowerCase();
    if (text.trim().isEmpty || _rangeRe.hasMatch(text)) return null;
    if (!_timeRe.hasMatch(text)) return null;
    final today = t.toUtc().add(const Duration(hours: 7)).weekday - 1;
    final out = <int>[];
    for (final rule in text.split(';')) {
      if (!_runsOn(rule, today)) continue;
      for (final m in _timeRe.allMatches(rule)) {
        out.add(int.parse(m[1]!) * 60 + int.parse(m[2]!));
      }
    }
    return out..sort();
  }

  static bool _runsOn(String rule, int day) {
    final dayMatches = _dayRe.allMatches(rule).toList();
    if (dayMatches.isEmpty) return true;
    for (final m in dayMatches) {
      final a = _days.indexOf(m[1]!);
      final b = m[2] == null ? a : _days.indexOf(m[2]!);
      for (var d = a; ; d = (d + 1) % 7) {
        if (d == day) return true;
        if (d == b) break;
      }
    }
    return false;
  }

  /// When vehicles leave the first stop on the Vietnam-time day of [t], in
  /// minutes after that day's midnight (past 1440 for hours that run over
  /// midnight): the mapped departures, and one every [headwayMin] through
  /// the mapped hours. Null when the data does not say: hours without a
  /// headway on that day, or on other days when that day has no departures,
  /// or no times at all.
  List<int>? scheduleOn(DateTime t) {
    final today = t.toUtc().add(const Duration(hours: 7)).weekday - 1;
    final every = headwayMin;
    final out = <int>{};
    for (final rule in openingHours.toLowerCase().split(';')) {
      if (!_runsOn(rule, today)) continue;
      final ranges = _rangeRe.allMatches(rule).toList();
      final single = _timeRe.allMatches(rule.replaceAll(_rangeRe, '')).toList();
      if (ranges.isEmpty && single.isEmpty) return null;
      if (ranges.isNotEmpty && every == null) return null;
      for (final m in ranges) {
        final open = int.parse(m[1]!) * 60 + int.parse(m[2]!);
        var close = int.parse(m[3]!) * 60 + int.parse(m[4]!);
        if (close <= open) close += 1440;
        for (var d = open; d <= close; d += every!) {
          out.add(d);
        }
      }
      for (final m in single) {
        out.add(int.parse(m[1]!) * 60 + int.parse(m[2]!));
      }
    }
    if (out.isEmpty && every == null && _rangeRe.hasMatch(openingHours)) {
      return null;
    }
    return out.toList()..sort();
  }

  String get label {
    if (ref.isNotEmpty) return ref;
    return mode == TransitMode.metro ? 'Metro' : '?';
  }

  String get modeLabel => switch (mode) {
    TransitMode.bus => tr('Xe buýt', 'Bus'),
    TransitMode.metro => 'Metro',
    TransitMode.ferry => tr('Buýt sông', 'Waterbus'),
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

  /// Joins per-city files, each with its own stop list. Every stop carries
  /// its place in the full list, so a stop served from two cities is merged
  /// back into one and stops keep the order of the full list.
  static TransitData fromParts(String generated, List<Uint8List> parts) {
    final byOrder = <int, List>{};
    final routes = <Map<String, dynamic>>[];
    final pending = <(Map<String, dynamic>, List<int>)>[];
    for (final part in parts) {
      final j = jsonDecode(utf8.decode(gzip.decode(part))) as Map;
      final local = [
        for (final s in j['stops'] as List)
          (byOrder[s[3] as int] ??= s as List)[3] as int,
      ];
      for (final r in (j['routes'] as List).cast<Map<String, dynamic>>()) {
        pending.add((r, [for (final s in r['stops'] as List) local[s as int]]));
        routes.add(r);
      }
    }
    final order = byOrder.keys.toList()..sort();
    final index = {for (var i = 0; i < order.length; i++) order[i]: i};
    for (final (r, stops) in pending) {
      r['stops'] = [for (final s in stops) index[s]!];
    }
    return _build(generated, [for (final o in order) byOrder[o]!], routes);
  }

  static TransitData fromJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return _build(
      j['generated'] as String? ?? '',
      j['stops'] as List,
      j['routes'] as List,
    );
  }

  static TransitData _build(String generated, List rawStops, List rawRoutes) {
    final stops = <Stop>[
      for (var i = 0; i < rawStops.length; i++)
        Stop(
          i,
          (rawStops[i][0] as num).toDouble(),
          (rawStops[i][1] as num).toDouble(),
          rawStops[i][2] as String,
        ),
    ];
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
        scheduleFields: r['schedf'] as String? ?? '',
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
    return TransitData(generated, stops, routes);
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
