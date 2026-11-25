import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/geo.dart';
import '../data/transit_data.dart';
import 'common.dart';
import 'route_detail_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final _map = MapController();
  Geo _center = AppState.defaultCenter;
  Geo? _me;
  bool _locating = false;

  Future<void> _locate() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    try {
      final g = await app.locate();
      if (!mounted) return;
      setState(() {
        _me = g;
        _center = g;
      });
      _map.move(ll(g), 16);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showStop(Stop s) {
    final data = context.read<AppState>().data!;
    final routes = s.routes.map((i) => data.routes[i]).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                s.displayName,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final r in routes)
              ListTile(
                leading: SizedBox(
                  width: 76,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: LineBadge(r),
                  ),
                ),
                title: Text(
                  r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RouteDetailScreen(route: r),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = context.read<AppState>().data!;
    final near = data.stopsNear(_center, 600);
    return Scaffold(
      appBar: AppBar(title: const Text('Trạm gần đây')),
      floatingActionButton: FloatingActionButton(
        key: const Key('locate'),
        onPressed: _locating ? null : _locate,
        child: _locating
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location_rounded),
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: ll(_center),
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onPositionChanged: (camera, hasGesture) {
                      final c = geoOf(camera.center);
                      if (distanceBetween(c, _center) > 60) {
                        setState(() => _center = c);
                      }
                    },
                  ),
                  children: [
                    const OsmTileLayer(),
                    MarkerLayer(
                      markers: [
                        for (final (s, _) in near)
                          dotMarker(
                            s.geo,
                            s.routes.isEmpty
                                ? walkColor
                                : modeColor(data.routes[s.routes.first]),
                            onTap: () => _showStop(s),
                          ),
                        if (_me != null)
                          pinMarker(
                            _me!,
                            const Color(0xFF2563EB),
                            Icons.person_pin_circle_rounded,
                          ),
                      ],
                    ),
                    const OsmAttribution(),
                  ],
                ),
                const IgnorePointer(
                  child: Icon(Icons.add, size: 22, color: Colors.black54),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: t.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '${near.length} trạm trong bán kính 600 m quanh tâm bản đồ',
              style: t.textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: near.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Không có trạm nào quanh đây. Kéo bản đồ hoặc bấm nút định vị.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: near.length,
                    itemBuilder: (context, i) {
                      final (s, d) = near[i];
                      final labels = <String>{
                        for (final ri in s.routes) data.routes[ri].label,
                      };
                      return ListTile(
                        leading: Icon(
                          s.routes.isEmpty
                              ? Icons.place_outlined
                              : modeIcon(data.routes[s.routes.first].mode),
                          color: s.routes.isEmpty
                              ? walkColor
                              : modeColor(data.routes[s.routes.first]),
                        ),
                        title: Text(
                          s.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Tuyến ${labels.take(10).join(', ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(fmtDistance(d)),
                        onTap: () => _showStop(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
