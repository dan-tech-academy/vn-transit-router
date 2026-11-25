import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/transit_data.dart';
import '../routing/router.dart' as routing;
import 'common.dart';

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

  @override
  void initState() {
    super.initState();
    final data = context.read<AppState>().data!;
    _directions =
        widget.directions ??
        data.routes.where((r) => r.lineKey == widget.route.lineKey).toList();
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
              tooltip: 'Đổi chiều',
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
                    '${r.stops.length} trạm',
                    fmtDistance(r.dist.last),
                    r.headwayMin != null
                        ? '$headway phút/chuyến'
                        : '~$headway phút/chuyến (giả định)',
                    if (r.openingHours.isNotEmpty) r.openingHours,
                    if (r.charge.isNotEmpty) 'vé ${r.charge}',
                    if (r.operator.isNotEmpty) r.operator,
                    if (r.scheduleSource.isNotEmpty)
                      '${r.scheduleFields.isEmpty ? 'giờ chạy' : r.scheduleFields} theo ${r.scheduleSource}',
                  ].join(' · '),
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
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
                  subtitle: others.isEmpty
                      ? null
                      : Text('Chuyển tuyến: $others'),
                  trailing: Text(
                    fmtDistance(r.dist[i]),
                    style: t.textTheme.bodySmall,
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
