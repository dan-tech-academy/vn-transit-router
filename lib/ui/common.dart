import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/geo.dart';
import '../data/transit_data.dart';
import '../l10n.dart';
import '../routing/router.dart';

const walkColor = Color(0xFFB45309);

/// Walking colour for text and icons drawn on the app's own surfaces.
Color walkInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFBBF24)
    : walkColor;

const originColor = Color(0xFF4D7C0F);
const destColor = Color(0xFFDC2626);

/// Persistent folder for viewed map tiles; set at startup.
String? tileCacheDir;

Color modeColor(TransitRoute r) {
  if (r.colour.startsWith('#') && r.colour.length == 7) {
    final v = int.tryParse(r.colour.substring(1), radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return modeTint(r.mode);
}

/// One colour per kind of vehicle, whatever colour the line itself has.
Color modeTint(TransitMode m) => switch (m) {
  TransitMode.bus => const Color(0xFF4D7C0F),
  TransitMode.metro => const Color(0xFF7C3AED),
  TransitMode.ferry => const Color(0xFF0E7490),
};

/// Readable text colour on [c]; some lines are tagged with very light colours.
Color onColor(Color c) =>
    c.computeLuminance() > 0.45 ? const Color(0xFF12422C) : Colors.white;

IconData modeIcon(TransitMode m) => switch (m) {
  TransitMode.bus => Icons.directions_bus_rounded,
  TransitMode.metro => Icons.subway_rounded,
  TransitMode.ferry => Icons.directions_boat_rounded,
};

LatLng ll(Geo g) => LatLng(g.lat, g.lon);
Geo geoOf(LatLng p) => Geo(p.latitude, p.longitude);

/// Whole minutes, never 0 for a leg that takes any time.
int fmtMinutes(int seconds) =>
    seconds <= 0 ? 0 : (seconds / 60).round().clamp(1, 1 << 31);

String fmtDuration(int seconds) {
  final m = fmtMinutes(seconds);
  if (m < 60) return tr('$m phút', '$m min');
  return tr('${m ~/ 60} giờ ${m % 60} phút', '${m ~/ 60} h ${m % 60} min');
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
          Icon(modeIcon(route.mode), size: large ? 18 : 14, color: onColor(c)),
          const SizedBox(width: 4),
          Text(
            route.label,
            style: TextStyle(
              color: onColor(c),
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
    // Tiles the user has viewed stay on the device and show when offline.
    tileProvider: NetworkTileProvider(
      cachingProvider: tileCacheDir == null
          ? null
          : BuiltInMapCachingProvider.getOrCreateInstance(
              cacheDirectory: tileCacheDir,
              maxCacheSize: 300000000,
              // Keep showing viewed tiles offline after the server's expiry.
              overrideFreshAge: const Duration(days: 30),
            ),
    ),
  );
}

class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) => const SimpleAttributionWidget(
    source: Text(
      'OpenStreetMap contributors',
      style: TextStyle(color: Colors.black87),
    ),
    backgroundColor: Color(0xCCFFFFFF),
  );
}

Marker dotMarker(
  Geo g,
  Color color, {
  double size = 14,
  VoidCallback? onTap,
  String? label,
}) => Marker(
  point: ll(g),
  width: size + 12,
  height: size + 12,
  child: Semantics(
    label: label,
    button: onTap != null,
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
  ),
);

/// Room to keep clear of the floating bar and the sheet when fitting a trip,
/// shrunk on short screens so some map is always left to fit into.
EdgeInsets fitPadding(double height, double top, double bottom) {
  final room = (height - 120).clamp(0.0, double.infinity);
  final k = top + bottom > room ? room / (top + bottom) : 1.0;
  return EdgeInsets.fromLTRB(40, top * k, 40, bottom * k);
}

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

String fmtDateTime(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} ${fmtClock(t)}';

List<Polyline> legPolylines(Itinerary it) => [
  for (final l in it.legs)
    if (l.kind == LegKind.walk)
      Polyline(
        points: l.path.map(ll).toList(),
        strokeWidth: 5,
        color: walkColor,
        pattern: const StrokePattern.dotted(),
      )
    else
      Polyline(
        points: l.path.map(ll).toList(),
        strokeWidth: 6,
        color: modeColor(l.route!),
        borderStrokeWidth: 2,
        borderColor: Colors.white,
      ),
];

/// Sheet over a full-screen map: rounded top, drag handle, map credit.
Widget mapSheet(
  BuildContext context, {
  required double initial,
  required double min,
  required double max,
  DraggableScrollableController? controller,
  required List<Widget> Function(BuildContext) children,
}) {
  final t = Theme.of(context);
  return DraggableScrollableSheet(
    controller: controller,
    initialChildSize: initial,
    minChildSize: min,
    maxChildSize: max,
    snap: true,
    builder: (context, scroll) => Material(
      color: t.colorScheme.surface,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      // The handle and the map credit stay put while the content scrolls.
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            PinnedHeaderSliver(
              child: ColoredBox(
                color: t.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '© OpenStreetMap',
                          style: t.textTheme.labelSmall?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.list(children: children(context)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Map tiles stay light in the dark theme, so status icons must stay dark.
const mapStatusBar = AnnotatedRegion<SystemUiOverlayStyle>(
  value: SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ),
  child: SizedBox.expand(),
);

/// The torn edge between a ticket's stub and its body.
class Perforation extends CustomPainter {
  final Color stub;
  final Color paper;
  const Perforation(this.stub, this.paper);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width / 2, size.height),
      Paint()..color = stub,
    );
    final hole = Paint()..color = paper;
    for (var y = 6.0; y < size.height; y += 12) {
      canvas.drawCircle(Offset(size.width / 2, y), 4, hole);
    }
  }

  @override
  bool shouldRepaint(Perforation old) => old.stub != stub || old.paper != paper;
}

/// A ticket: stub in [color] showing [icon] and [label], then [child].
class StubCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String? label;
  final Widget child;
  final VoidCallback? onTap;
  const StubCard({
    super.key,
    required this.color,
    required this.icon,
    this.label,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final paper = Theme.of(context).colorScheme.surfaceContainerLow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: paper,
        elevation: 1,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 72,
                  color: color,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: Colors.white,
                        size: label == null ? 26 : 22,
                      ),
                      if (label != null) ...[
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label!,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                CustomPaint(
                  size: const Size(8, double.infinity),
                  painter: Perforation(color, paper),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating bar over a full-screen map.
class MapTopBar extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final bool back;
  const MapTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.back = true,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 4,
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                if (back) const BackButton() else const SizedBox(width: 20),
                Expanded(child: title),
                ...actions,
                if (actions.isEmpty) const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shows [g] in the part of a full-screen map left clear by bar and sheet.
CameraFit fitPoint(BuildContext context, Geo g, double sheet, double zoom) {
  final h = MediaQuery.sizeOf(context).height;
  return CameraFit.coordinates(
    coordinates: [ll(g)],
    minZoom: zoom,
    maxZoom: zoom,
    padding: fitPadding(h, MediaQuery.paddingOf(context).top + 80, h * sheet),
  );
}
