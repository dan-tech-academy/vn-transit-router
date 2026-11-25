import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/geo.dart';

class WalkPath {
  final List<Geo> path;
  final int metres;
  const WalkPath(this.path, this.metres);
}

/// Street-following walking paths from the FOSSGIS OSRM foot profile
/// (routing.openstreetmap.de). Only called when an itinerary is opened.
class WalkRouter {
  static const _host = 'routing.openstreetmap.de';
  static const _headers = {
    'User-Agent':
        'vn-transit-router/1.0 (github.com/dan-tech-academy/vn-transit-router)',
  };
  final http.Client _client;
  final _cache = <String, WalkPath>{};
  WalkRouter([http.Client? client]) : _client = client ?? http.Client();

  static String _c(Geo g) =>
      '${g.lon.toStringAsFixed(5)},${g.lat.toStringAsFixed(5)}';

  /// Null when offline or the service has no path.
  Future<WalkPath?> route(Geo a, Geo b) async {
    final key = '${_c(a)};${_c(b)}';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final res = await _client
          .get(
            Uri.https(_host, '/routed-foot/route/v1/foot/$key', {
              'overview': 'full',
              'geometries': 'polyline',
            }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['code'] != 'Ok') return null;
      final r = (j['routes'] as List).first as Map<String, dynamic>;
      final line = decodePolyline(r['geometry'] as String);
      if (line.length < 2) return null;
      // Join the snapped street path to the real end points.
      final path = [a, ...line, b];
      var metres = 0.0;
      for (var i = 1; i < path.length; i++) {
        metres += distanceBetween(path[i - 1], path[i]);
      }
      return _cache[key] = WalkPath(path, metres.round());
    } catch (_) {
      return null;
    }
  }
}
