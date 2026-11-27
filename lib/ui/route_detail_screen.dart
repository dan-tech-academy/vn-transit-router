import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/transit_data.dart';
import '../l10n.dart';
import '../routing/router.dart' as routing;
import '../routing/vehicles.dart';
import 'common.dart';
import 'stop_detail_screen.dart';

String _fields(String f) {
  if (f.isEmpty) return tr('giờ chạy', 'schedule');
  if (appLang != 'en') return f;
  return f
      .replaceAll('giờ chạy', 'hours')
      .replaceAll('giãn cách', 'frequency')
      .replaceAll('giá vé', 'fare');
}

class RouteDetailScreen extends StatefulWidget {
  final TransitRoute route;
  final List<TransitRoute>? directions;
  const RouteDetailScreen({super.key, required this.route, this.directions});

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late TransitRoute _route = widget.route;
  late List<TransitRoute> _directions;
  final _map = MapController();
  int? _selected;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Estimated vehicles move with the clock.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    final data = context.read<AppState>().data!;
    _directions =
        widget.directions ??
        data.routes.where((r) => r.lineKey == widget.route.lineKey).toList();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _vehiclesLine(List<VehicleEstimate> vehicles, DateTime now) {
    if (vehicles.isNotEmpty) {
      final n = vehicles.length;
      return tr(
        '$n xe đang chạy · vị trí ước tính theo lịch, không phải GPS',
        '$n ${n == 1 ? 'vehicle' : 'vehicles'} running · positions estimated from the schedule, not GPS',
      );
    }
    final next = nextDeparture(_route, now);
    if (next == null) {
      return tr(
        'Theo lịch, hiện không có xe đang chạy',
        'No vehicle is running now, by the schedule',
      );
    }
    final at =
        '${(next ~/ 60).toString().padLeft(2, '0')}:${(next % 60).toString().padLeft(2, '0')}';
    return tr(
      'Theo lịch, chuyến kế xuất bến lúc $at',
      'By the schedule, the next one leaves at $at',
    );
  }

  void _switchDirection() {
    final i = _directions.indexOf(_route);
    setState(() {
      _route = _directions[(i + 1) % _directions.length];
      _selected = null;
    });
    _map.fitCamera(_fit(_route));
  }

  CameraFit _fit(TransitRoute r) {
    final h = MediaQuery.sizeOf(context).height;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(r.shape.map(ll).toList()),
      padding: fitPadding(
        h,
        MediaQuery.paddingOf(context).top + 90,
        h * 0.5 + 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = context.read<AppState>().data!;
    final r = _route;
    final color = modeColor(r);
    final shape = r.shape.map(ll).toList();
    final now = DateTime.now();
    final vehicles = estimateVehicles(r, now);
    final arriving = <int, int>{
      for (final v in vehicles ?? const <VehicleEstimate>[])
        v.nextStop: v.secondsToNext,
    };
    final headway =
        r.headwayMin ?? routing.RouterConfig.defaultHeadwayMin(r.mode);
    Widget fact(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: t.textTheme.labelMedium)),
        ],
      ),
    );
    return Scaffold(
      body: Stack(
        children: [
          mapStatusBar,
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCameraFit: _fit(r),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              const OsmTileLayer(),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: shape,
                    strokeWidth: 5,
                    color: color,
                    borderStrokeWidth: 2,
                    borderColor: Colors.white,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (var i = 0; i < r.stops.length; i++)
                    dotMarker(
                      data.stops[r.stops[i]].geo,
                      color,
                      size: i == _selected ? 18 : 9,
                    ),
                  for (final v in vehicles ?? const <VehicleEstimate>[])
                    Marker(
                      point: ll(v.position),
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 3),
                          ],
                        ),
                        child: Icon(
                          modeIcon(r.mode),
                          size: 16,
                          color: onColor(color),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          MapTopBar(
            title: Row(
              children: [
                LineBadge(r, large: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.modeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (_directions.length > 1) ...[
                IconButton(
                  key: const Key('switch-direction'),
                  tooltip: tr('Đổi chiều', 'Switch direction'),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onPressed: _switchDirection,
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          mapSheet(
            context,
            initial: 0.5,
            min: 0.2,
            max: 0.85,
            children: (context) => [
              Text(
                r.title,
                style: t.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  fact(
                    Icons.pin_drop_outlined,
                    tr('${r.stops.length} trạm', '${r.stops.length} stops'),
                  ),
                  fact(Icons.straighten_rounded, fmtDistance(r.dist.last)),
                  fact(
                    Icons.timelapse_rounded,
                    r.headwayMin != null
                        ? tr('$headway phút/chuyến', 'every $headway min')
                        : tr(
                            '~$headway phút/chuyến (giả định)',
                            '~every $headway min (assumed)',
                          ),
                  ),
                  if (r.openingHours.isNotEmpty)
                    fact(Icons.schedule_rounded, r.openingHours),
                  if (r.charge.isNotEmpty)
                    fact(Icons.confirmation_number_outlined, r.charge),
                ],
              ),
              if (r.operator.isNotEmpty || r.scheduleSource.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (r.operator.isNotEmpty) r.operator,
                    if (r.scheduleSource.isNotEmpty)
                      '${_fields(r.scheduleFields)} ${tr('theo', 'from')} ${r.scheduleSource}',
                  ].join(' · '),
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (vehicles != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        modeIcon(r.mode),
                        size: 18,
                        color: t.colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _vehiclesLine(vehicles, now),
                          key: const Key('estimated-vehicles'),
                          style: t.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              for (var i = 0; i < r.stops.length; i++)
                _stopRow(context, data, r, i, color, arriving[i]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stopRow(
    BuildContext context,
    TransitData data,
    TransitRoute r,
    int i,
    Color color,
    int? due,
  ) {
    final t = Theme.of(context);
    final s = data.stops[r.stops[i]];
    final others = {
      for (final ri in s.routes)
        if (data.routes[ri].lineKey != r.lineKey) data.routes[ri].label,
    }.take(8).join(', ');
    final first = i == 0, last = i == r.stops.length - 1;
    final end = first || last;
    final picked = i == _selected;
    Widget rail(bool show) => Expanded(
      child: Container(width: 5, color: show ? color : Colors.transparent),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _selected = i);
        _map.fitCamera(fitPoint(context, s.geo, 0.5, 16));
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(children: [rail(!first), rail(!last)]),
                  Container(
                    width: end || picked ? 18 : 12,
                    height: end || picked ? 18 : 12,
                    decoration: BoxDecoration(
                      color: picked ? color : t.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s.displayName,
                      style: t.textTheme.bodyMedium?.copyWith(
                        fontWeight: end || picked
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    if (due != null)
                      Text(
                        due < 60
                            ? tr(
                                'Xe sắp tới (ước tính)',
                                'Vehicle due now (estimate)',
                              )
                            : tr(
                                'Xe tới sau ~${(due / 60).round()} phút (ước tính)',
                                'Vehicle in ~${(due / 60).round()} min (estimate)',
                              ),
                        style: t.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (others.isNotEmpty)
                      Text(
                        '${tr('Chuyển tuyến', 'Transfer')}: $others',
                        style: t.textTheme.bodySmall?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Center(
              child: Text(
                fmtDistance(r.dist[i]),
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Center(
              child: IconButton(
                key: Key('stop-info-$i'),
                tooltip: tr('Chi tiết trạm', 'Stop details'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.info_outline, size: 20),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StopDetailScreen(stop: s)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
