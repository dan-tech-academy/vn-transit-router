import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/geo.dart';

class Place {
  final String name;
  final String subtitle;
  final Geo geo;
  final bool isStop;
  const Place(this.name, this.subtitle, this.geo, {this.isStop = false});

  Map<String, dynamic> toJson() => {
    'n': name,
    's': subtitle,
    'la': geo.lat,
    'lo': geo.lon,
    'st': isStop,
  };

  static Place fromJson(Map<String, dynamic> j) => Place(
    j['n'] as String,
    j['s'] as String,
    Geo((j['la'] as num).toDouble(), (j['lo'] as num).toDouble()),
    isStop: j['st'] as bool? ?? false,
  );
}

/// Online place search backed by OpenStreetMap Nominatim.
class Geocoder {
  static const _host = 'nominatim.openstreetmap.org';
  static const _headers = {
    'User-Agent':
        'vn-transit-router/1.0 (github.com/dan-tech-academy/vn-transit-router)',
    'Accept-Language': 'vi',
  };
  final http.Client _client;
  Geocoder([http.Client? client]) : _client = client ?? http.Client();

  Future<List<Place>> search(String query, {Geo? near}) async {
    final params = {
      'format': 'jsonv2',
      'q': query,
      'countrycodes': 'vn',
      'limit': '8',
      'addressdetails': '0',
    };
    if (near != null) {
      // Bias results towards the user's area without sending the exact fix.
      final lat = near.lat.roundToDouble(), lon = near.lon.roundToDouble();
      params['viewbox'] = '${lon - 1},${lat + 1},${lon + 1},${lat - 1}';
    }
    final res = await _client
        .get(Uri.https(_host, '/search', params), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('Nominatim HTTP ${res.statusCode}');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return [for (final e in list) _place(e as Map<String, dynamic>)];
  }

  Future<Place?> reverse(Geo p) async {
    final res = await _client
        .get(
          Uri.https(_host, '/reverse', {
            'format': 'jsonv2',
            'lat': '${p.lat}',
            'lon': '${p.lon}',
            'zoom': '18',
          }),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (j['display_name'] == null) return null;
    final place = _place(j);
    return Place(place.name, place.subtitle, p);
  }

  Place _place(Map<String, dynamic> e) {
    final display = e['display_name'] as String;
    final parts = display.split(', ');
    final name = (e['name'] as String?)?.isNotEmpty == true
        ? e['name'] as String
        : parts.first;
    final rest = parts
        .where((p) => p != name && p != 'Việt Nam')
        .take(3)
        .join(', ');
    return Place(
      name,
      rest,
      Geo(double.parse('${e['lat']}'), double.parse('${e['lon']}')),
    );
  }
}
