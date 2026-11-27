import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../routing/router.dart';
import '../services/geocoder.dart';
import 'common.dart';
import 'route_detail_screen.dart';
import 'stop_detail_screen.dart';

/// Plain-text summary of an itinerary for sharing.
String itineraryShareText(
  Itinerary it,
  Place from,
  Place to,
  DateTime departAt,
) {
  final b = StringBuffer()
    ..writeln('${AppState.placeName(from)} → ${AppState.placeName(to)}')
    ..writeln(
      '${fmtDateTime(departAt)} – ${fmtClock(departAt.add(Duration(seconds: it.seconds)))}'
      ' (${fmtDuration(it.seconds)})'
      '${it.fare > 0 ? ' · ${tr('vé', 'fare')} ~${fmtMoney(it.fare)}' : ''}',
    );
  var clock = departAt;
  var n = 1;
  for (final l in it.legs) {
    // A ride is listed at its boarding time, after the wait.
    final at = fmtClock(clock.add(Duration(seconds: l.waitSeconds)));
    clock = clock.add(Duration(seconds: l.seconds + l.waitSeconds));
    if (l.kind == LegKind.walk) {
      b.writeln(
        tr(
          '$n. $at Đi bộ ${fmtDistance(l.metres)} đến ${_name(l.toName)}',
          '$n. $at Walk ${fmtDistance(l.metres)} to ${_name(l.toName)}',
        ),
      );
    } else {
      final r = l.route!;
      b.writeln(
        tr(
          '$n. $at ${r.modeLabel} ${r.ref} từ ${l.fromName} đến ${l.toName} (${l.stopCount} trạm)',
          '$n. $at ${r.modeLabel} ${r.ref} from ${l.fromName} to ${l.toName} (${l.stopCount} stops)',
        ),
      );
    }
    n++;
  }
  b.write(
    tr(
      'Thời gian và giá vé là ước tính. Ghee, dữ liệu © OpenStreetMap.',
      'Times and fares are estimates. Ghee, data © OpenStreetMap.',
    ),
  );
  return b.toString();
}

String _name(String n) =>
    n == AppState.myLocationName ? tr('Vị trí của tôi', 'My location') : n;

class ItineraryScreen extends StatefulWidget {
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
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  late Itinerary itinerary = widget.itinerary;
  Place get from => widget.from;
  Place get to => widget.to;
  DateTime get departAt => widget.departAt;

  /// null: loading, true: walks follow streets, false: straight lines.
  bool? _streets = false;

  /// The street walk is too long to catch a vehicle with a fixed departure.
  bool _tooLate = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    if (app.streetWalking &&
        itinerary.legs.any((l) => l.kind == LegKind.walk && l.metres > 0)) {
      _streets = null;
      _loadStreets(app);
    }
  }

  Future<void> _loadStreets(AppState app) async {
    final speed = app.router!.config.walkSpeed;
    final legs = await Future.wait([
      for (final l in itinerary.legs)
        if (l.kind == LegKind.walk && l.path.length >= 2 && l.metres > 0)
          app.walkRouter
              .route(l.path.first, l.path.last)
              .then(
                (w) => w == null
                    ? null
                    : l.rewalk(w.path, w.metres, (w.metres / speed).round()),
              )
        else
          Future<Leg?>.value(l),
    ]);
    if (!mounted) return;
    setState(() {
      // Keep the estimate unless every walk was routed.
      // ... and no fixed departure is missed by the longer walk.
      final timed = legs.contains(null)
          ? null
          : withWalks(itinerary.legs, [for (final l in legs) l!], departAt);
      _streets = timed != null;
      _tooLate = timed == null && !legs.contains(null);
      if (timed != null) itinerary = Itinerary(timed);
    });
  }

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
      pinMarker(from.geo, const Color(0xFF4D7C0F), Icons.trip_origin),
      pinMarker(to.geo, const Color(0xFFDC2626), Icons.location_on),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${fmtDuration(it.seconds)} · ${AppState.placeName(from)} → ${AppState.placeName(to)}',
          style: t.textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            key: const Key('share'),
            tooltip: tr('Chia sẻ', 'Share'),
            icon: const Icon(Icons.share_rounded),
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: itineraryShareText(it, from, to, departAt)),
            ),
          ),
        ],
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
                  it.transfers == 0
                      ? tr('Đi thẳng', 'Direct')
                      : tr(
                          '${it.transfers} lần chuyển',
                          '${it.transfers} transfer${it.transfers > 1 ? 's' : ''}',
                        ),
                tr(
                  'Đi bộ ${fmtDistance(it.walkMetres)}',
                  'Walk ${fmtDistance(it.walkMetres)}',
                ),
                if (it.fare > 0)
                  tr('Vé ~${fmtMoney(it.fare)}', 'Fare ~${fmtMoney(it.fare)}'),
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
                if (_streets == false &&
                    !_tooLate &&
                    it.legs.any((l) => l.kind == LegKind.walk && l.metres > 0))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('load-streets'),
                      icon: const Icon(Icons.directions_walk_rounded, size: 18),
                      label: Text(
                        tr(
                          'Tải đường đi bộ theo phố (cần mạng)',
                          'Load street walking paths (online)',
                        ),
                      ),
                      onPressed: () {
                        setState(() => _streets = null);
                        _loadStreets(context.read<AppState>());
                      },
                    ),
                  ),
                Text(
                  '${tr('Thời gian và giá vé là ước tính từ quãng đường và tần suất tuyến, không phải lịch chạy thực tế.', 'Times and fares are estimated from distance and line frequency, not real timetables.')} '
                  '${switch (_streets) {
                    null => tr('Đang tải đường đi bộ theo phố...', 'Loading street walking paths...'),
                    true => tr('Đường đi bộ theo phố từ OSRM (routing.openstreetmap.de).', 'Street walking paths from OSRM (routing.openstreetmap.de).'),
                    false when _tooLate => tr('Đi bộ theo phố lâu hơn ước tính nên có thể lỡ chuyến xe chạy theo giờ cố định; lộ trình giữ ước tính đường thẳng.', 'Walking along streets takes longer than estimated and may miss a fixed departure; the straight-line estimate is kept.'),
                    false => tr('Đường đi bộ vẽ theo đường thẳng.', 'Walking is drawn as straight lines.'),
                  }}',
                  key: const Key('walk-note'),
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
          AppState.placeName(to),
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
        Text(
          _name(l.fromName),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            'Đi bộ ${fmtDistance(l.metres)} (khoảng ${fmtDuration(l.seconds)}) đến ${_name(l.toName)}',
            'Walk ${fmtDistance(l.metres)} (about ${fmtDuration(l.seconds)}) to ${_name(l.toName)}',
          ),
        ),
      ],
    ),
  );

  Widget _rideStep(BuildContext context, Leg l, DateTime start) {
    final r = l.route!;
    final t = Theme.of(context);
    final data = context.read<AppState>().data!;
    void openStop(int pos) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StopDetailScreen(stop: data.stops[r.stops[pos]]),
      ),
    );
    final towards = r.to.isEmpty ? r.title : r.to;
    return _Step(
      time: fmtClock(start),
      color: modeColor(r),
      icon: modeIcon(r.mode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => openStop(l.fromPos),
            child: Text(
              l.fromName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
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
                    tr(
                      '${r.modeLabel} hướng $towards',
                      '${r.modeLabel} towards $towards',
                    ),
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
            tr(
              'Chờ khoảng ${fmtDuration(l.waitSeconds)} · đi ${l.stopCount} trạm '
                  '(${fmtDistance(l.metres)}, ${fmtDuration(l.seconds)}) · vé ~${fmtMoney(l.fare)}',
              'Wait about ${fmtDuration(l.waitSeconds)} · ride ${l.stopCount} stops '
                  '(${fmtDistance(l.metres)}, ${fmtDuration(l.seconds)}) · fare ~${fmtMoney(l.fare)}',
            ),
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => openStop(l.toPos),
            child: Text(tr('Xuống tại ${l.toName}', 'Get off at ${l.toName}')),
          ),
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
