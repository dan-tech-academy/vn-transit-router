import 'dart:math' as math;

class Geo {
  final double lat;
  final double lon;
  const Geo(this.lat, this.lon);

  @override
  String toString() => '$lat,$lon';
}

const double _earthDiameter = 12742000;

double haversine(double lat1, double lon1, double lat2, double lon2) {
  const rad = math.pi / 180;
  final dLat = (lat2 - lat1) * rad;
  final dLon = (lon2 - lon1) * rad;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * rad) *
          math.cos(lat2 * rad) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return _earthDiameter * math.asin(math.sqrt(h));
}

double distanceBetween(Geo a, Geo b) => haversine(a.lat, a.lon, b.lat, b.lon);

/// Decodes a Google encoded polyline (precision 5).
List<Geo> decodePolyline(String s) {
  final out = <Geo>[];
  var i = 0, lat = 0, lon = 0;
  while (i < s.length) {
    for (var k = 0; k < 2; k++) {
      var shift = 0, result = 0, b = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final d = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      if (k == 0) {
        lat += d;
      } else {
        lon += d;
      }
    }
    out.add(Geo(lat / 1e5, lon / 1e5));
  }
  return out;
}

const _from =
    'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Lowercases and strips Vietnamese diacritics for search matching.
String foldVi(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b.toString();
}
