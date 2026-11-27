import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/geo.dart';
import '../data/transit_data.dart';
import '../l10n.dart';
import 'common.dart';
import 'stop_detail_screen.dart';

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

  void _showStop(Stop s) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => StopDetailScreen(stop: s)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = context.watch<AppState>().data!;
    final near = data.stopsNear(_center, 600);
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          mapStatusBar,
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
                          : modeTint(data.routes[s.routes.first].mode),
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
            ],
          ),
          const IgnorePointer(
            child: Icon(Icons.add, size: 26, color: Colors.black87),
          ),
          MapTopBar(
            back: false,
            title: Text(
              tr('Trạm gần đây', 'Nearby stops'),
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                key: const Key('locate'),
                tooltip: tr('Vị trí của tôi', 'My location'),
                onPressed: _locating ? null : _locate,
                icon: _locating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          mapSheet(
            context,
            initial: 0.4,
            min: 0.14,
            max: 0.85,
            children: (context) => [
              Text(
                tr('${near.length} trạm', '${near.length} stops'),
                style: t.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                tr(
                  'trong bán kính 600 m quanh tâm bản đồ',
                  'within 600 m of the map centre',
                ),
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (near.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    tr(
                      'Không có trạm nào quanh đây. Kéo bản đồ hoặc bấm nút định vị.',
                      'No stops around here. Drag the map or tap the locate button.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final (s, d) in near)
                StubCard(
                  color: s.routes.isEmpty
                      ? walkColor
                      : modeTint(data.routes[s.routes.first].mode),
                  icon: s.routes.isEmpty
                      ? Icons.place_outlined
                      : modeIcon(data.routes[s.routes.first].mode),
                  label: fmtDistance(d),
                  onTap: () => _showStop(s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        s.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tr('Tuyến', 'Lines')} ${{for (final ri in s.routes) data.routes[ri].label}.take(10).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
