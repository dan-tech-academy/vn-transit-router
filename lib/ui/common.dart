import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/geo.dart';
import '../data/transit_data.dart';

const walkColor = Color(0xFF64748B);

Color modeColor(TransitRoute r) {
  if (r.colour.startsWith('#') && r.colour.length == 7) {
    final v = int.tryParse(r.colour.substring(1), radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return switch (r.mode) {
    TransitMode.bus => const Color(0xFF0E9F6E),
    TransitMode.metro => const Color(0xFF2563EB),
    TransitMode.ferry => const Color(0xFF0891B2),
  };
}

IconData modeIcon(TransitMode m) => switch (m) {
  TransitMode.bus => Icons.directions_bus_rounded,
  TransitMode.metro => Icons.subway_rounded,
  TransitMode.ferry => Icons.directions_boat_rounded,
};

LatLng ll(Geo g) => LatLng(g.lat, g.lon);
Geo geoOf(LatLng p) => Geo(p.latitude, p.longitude);

String fmtDuration(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m phút';
  return '${m ~/ 60} giờ ${m % 60} phút';
}

String fmtDistance(num metres) => metres < 1000
    ? '${metres.round()} m'
    : '${(metres / 1000).toStringAsFixed(1)} km';

String fmtMoney(int vnd) {
  final s = vnd.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$bđ';
}

String fmtClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Pill showing a line number, e.g. a bus "19" or metro "L1".
class LineBadge extends StatelessWidget {
  final TransitRoute route;
  final bool large;
  const LineBadge(this.route, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    final c = modeColor(route);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 7,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            modeIcon(route.mode),
            size: large ? 18 : 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            route.label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: large ? 16 : 13,
            ),
          ),
        ],
      ),
    );
  }
}

class OsmTileLayer extends StatelessWidget {
  const OsmTileLayer({super.key});

  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'dev.dantech.vn_transit',
    maxZoom: 19,
  );
}

class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) => const SimpleAttributionWidget(
    source: Text('OpenStreetMap contributors'),
    backgroundColor: Color(0xCCFFFFFF),
  );
}

Marker dotMarker(Geo g, Color color, {double size = 14, VoidCallback? onTap}) =>
    Marker(
      point: ll(g),
      width: size + 12,
      height: size + 12,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
          ),
        ),
      ),
    );

Marker pinMarker(Geo g, Color color, IconData icon) => Marker(
  point: ll(g),
  width: 40,
  height: 40,
  alignment: Alignment.topCenter,
  child: Icon(
    icon,
    color: color,
    size: 40,
    shadows: const [
      Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
    ],
  ),
);
