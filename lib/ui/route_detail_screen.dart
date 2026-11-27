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
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(_route.shape.map(ll).toList()),
        padding: const EdgeInsets.all(32),
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            LineBadge(r, large: true),
            const SizedBox(width: 10),
            Expanded(child: Text(r.modeLabel, style: t.textTheme.titleMedium)),
          ],
        ),
        actions: [
          if (_directions.length > 1)
            IconButton(
              key: const Key('switch-direction'),
              tooltip: tr('Đổi chiều', 'Switch direction'),
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: _switchDirection,
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.32,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(shape),
                  padding: const EdgeInsets.all(32),
                ),
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
                const OsmAttribution(),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: t.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    tr('${r.stops.length} trạm', '${r.stops.length} stops'),
                    fmtDistance(r.dist.last),
                    r.headwayMin != null
                        ? tr('$headway phút/chuyến', 'every $headway min')
                        : tr(
                            '~$headway phút/chuyến (giả định)',
                            '~every $headway min (assumed)',
                          ),
                    if (r.openingHours.isNotEmpty) r.openingHours,
                    if (r.charge.isNotEmpty) '${tr('vé', 'fare')} ${r.charge}',
                    if (r.operator.isNotEmpty) r.operator,
                    if (r.scheduleSource.isNotEmpty)
                      '${_fields(r.scheduleFields)} ${tr('theo', 'from')} ${r.scheduleSource}',
                  ].join(' · '),
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (vehicles != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(modeIcon(r.mode), size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _vehiclesLine(vehicles, now),
                          key: const Key('estimated-vehicles'),
                          style: t.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: r.stops.length,
              itemBuilder: (context, i) {
                final s = data.stops[r.stops[i]];
                final others = {
                  for (final ri in s.routes)
                    if (data.routes[ri].lineKey != r.lineKey)
                      data.routes[ri].label,
                }.take(8).join(', ');
                final end = i == 0 || i == r.stops.length - 1;
                final due = arriving[i];
                return ListTile(
                  dense: true,
                  selected: i == _selected,
                  leading: Icon(
                    end ? Icons.radio_button_checked : Icons.circle_outlined,
                    size: end ? 20 : 14,
                    color: color,
                  ),
                  title: Text(
                    s.displayName,
                    style: TextStyle(
                      fontWeight: end ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: others.isEmpty && due == null
                      ? null
                      : Text(
                          [
                            if (due != null)
                              due < 60
                                  ? tr(
                                      'Xe sắp tới (ước tính)',
                                      'Vehicle due now (estimate)',
                                    )
                                  : tr(
                                      'Xe tới sau ~${(due / 60).round()} phút (ước tính)',
                                      'Vehicle in ~${(due / 60).round()} min (estimate)',
                                    ),
                            if (others.isNotEmpty)
                              '${tr('Chuyển tuyến', 'Transfer')}: $others',
                          ].join('\n'),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fmtDistance(r.dist[i]),
                        style: t.textTheme.bodySmall,
                      ),
                      IconButton(
                        key: Key('stop-info-$i'),
                        tooltip: tr('Chi tiết trạm', 'Stop details'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.info_outline, size: 20),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StopDetailScreen(stop: s),
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    setState(() => _selected = i);
                    _map.move(ll(s.geo), 16);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
