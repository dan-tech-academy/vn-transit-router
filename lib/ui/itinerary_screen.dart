import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../routing/router.dart';
import '../services/geocoder.dart';
import 'common.dart';
import 'route_detail_screen.dart';

class ItineraryScreen extends StatelessWidget {
  final Itinerary itinerary;
  final Place from;
  final Place to;
  final DateTime departAt;
  const ItineraryScreen({
    super.key,
    required this.itinerary,
    required this.from,
    required this.to,
    required this.departAt,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final it = itinerary;
    final allPoints = [for (final l in it.legs) ...l.path.map(ll)];
    if (allPoints.isEmpty) allPoints.add(const LatLng(10.7725, 106.6980));
    final samePoint = allPoints.every((p) => p == allPoints.first);
    final polylines = <Polyline>[
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
    final markers = <Marker>[
      for (final l in it.rides) ...[
        dotMarker(l.path.first, modeColor(l.route!)),
        dotMarker(l.path.last, modeColor(l.route!)),
      ],
      pinMarker(from.geo, const Color(0xFF0E9F6E), Icons.trip_origin),
      pinMarker(to.geo, const Color(0xFFDC2626), Icons.location_on),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${fmtDuration(it.seconds)} · ${from.name} → ${to.name}',
          style: t.textTheme.titleMedium,
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.36,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: samePoint
                    ? null
                    : CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(allPoints),
                        padding: const EdgeInsets.all(36),
                      ),
                initialCenter: allPoints.first,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                const OsmTileLayer(),
                PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
                const OsmAttribution(),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: t.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              [
                '${fmtClock(departAt)} – ${fmtClock(departAt.add(Duration(seconds: it.seconds)))}',
                if (!it.walkOnly)
                  it.transfers == 0 ? 'Đi thẳng' : '${it.transfers} lần chuyển',
                'Đi bộ ${fmtDistance(it.walkMetres)}',
                if (it.fare > 0) 'Vé ~${fmtMoney(it.fare)}',
              ].join(' · '),
              style: t.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                ..._steps(context),
                const SizedBox(height: 12),
                Text(
                  'Thời gian và giá vé là ước tính từ quãng đường và tần suất tuyến, '
                  'không phải lịch chạy thực tế. Đường đi bộ vẽ theo đường thẳng.',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _steps(BuildContext context) {
    final out = <Widget>[];
    var clock = departAt;
    for (final l in itinerary.legs) {
      final start = clock;
      clock = clock.add(Duration(seconds: l.seconds + l.waitSeconds));
      out.add(
        l.kind == LegKind.walk
            ? _walkStep(context, l, start)
            : _rideStep(context, l, start),
      );
    }
    out.add(
      _Step(
        time: fmtClock(clock),
        color: const Color(0xFFDC2626),
        icon: Icons.location_on,
        last: true,
        child: Text(
          to.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
    return out;
  }

  Widget _walkStep(BuildContext context, Leg l, DateTime start) => _Step(
    time: fmtClock(start),
    color: walkColor,
    icon: Icons.directions_walk_rounded,
    dashed: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.fromName, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Đi bộ ${fmtDistance(l.metres)} (khoảng ${fmtDuration(l.seconds)}) đến ${l.toName}',
        ),
      ],
    ),
  );

  Widget _rideStep(BuildContext context, Leg l, DateTime start) {
    final r = l.route!;
    final t = Theme.of(context);
    return _Step(
      time: fmtClock(start),
      color: modeColor(r),
      icon: modeIcon(r.mode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.fromName, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RouteDetailScreen(route: r)),
            ),
            child: Row(
              children: [
                LineBadge(r, large: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${r.modeLabel} hướng ${r.to.isEmpty ? r.title : r.to}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Chờ khoảng ${fmtDuration(l.waitSeconds)} · đi ${l.stopCount} trạm '
            '(${fmtDistance(l.metres)}, ${fmtDuration(l.seconds)}) · vé ~${fmtMoney(l.fare)}',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text('Xuống tại ${l.toName}'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String time;
  final Color color;
  final IconData icon;
  final Widget child;
  final bool dashed;
  final bool last;
  const _Step({
    required this.time,
    required this.color,
    required this.icon,
    required this.child,
    this.dashed = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                time,
                style: t.textTheme.labelMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 17, color: Colors.white),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: dashed ? 2 : 5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: dashed ? 0.45 : 1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: last ? 0 : 18),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
