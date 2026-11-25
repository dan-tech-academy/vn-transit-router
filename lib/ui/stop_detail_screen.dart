import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/transit_data.dart';
import '../l10n.dart';
import '../services/geocoder.dart';
import 'common.dart';
import 'route_detail_screen.dart';

/// A stop with every line serving it and shortcuts to plan from or to it.
class StopDetailScreen extends StatelessWidget {
  final Stop stop;
  const StopDetailScreen({super.key, required this.stop});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final app = context.watch<AppState>();
    final data = app.data!;
    final routes = stop.routes.map((i) => data.routes[i]).toList();
    final cities = {for (final r in routes) r.city}.join(', ');
    final place = Place(stop.displayName, cities, stop.geo, isStop: true);
    final color = routes.isEmpty ? walkColor : modeColor(routes.first);
    final saved = app.isSaved(place);

    void plan({Place? from, Place? to}) {
      app.planWith(from: from, to: to);
      Navigator.of(context).popUntil((r) => r.isFirst);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(stop.displayName),
        actions: [
          IconButton(
            key: const Key('save-stop'),
            tooltip: saved
                ? tr('Bỏ lưu', 'Remove from saved')
                : tr('Lưu địa điểm', 'Save place'),
            icon: Icon(saved ? Icons.star_rounded : Icons.star_border_rounded),
            onPressed: () => app.toggleSaved(place),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.26,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: ll(stop.geo),
                initialZoom: 17,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                const OsmTileLayer(),
                MarkerLayer(
                  markers: [pinMarker(stop.geo, color, Icons.location_on)],
                ),
                const OsmAttribution(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('from-here'),
                    icon: const Icon(Icons.trip_origin, size: 18),
                    label: Text(tr('Đi từ đây', 'From here')),
                    onPressed: () => plan(from: place),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('to-here'),
                    icon: const Icon(Icons.location_on, size: 18),
                    label: Text(tr('Đến đây', 'To here')),
                    onPressed: () => plan(to: place),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr(
                  '${routes.length} chiều tuyến đi qua trạm này',
                  '${routes.length} route directions serve this stop',
                ),
                style: t.textTheme.labelLarge,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
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
                    subtitle: Text(
                      [
                        r.modeLabel,
                        if (r.headwayMin != null)
                          tr(
                            '${r.headwayMin} phút/chuyến',
                            'every ${r.headwayMin} min',
                          ),
                        if (r.openingHours.isNotEmpty) r.openingHours,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RouteDetailScreen(route: r),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    tr(
                      'Giờ xe đến thực tế chưa có: các đơn vị vận hành chưa mở nguồn dữ liệu vị trí xe công khai.',
                      'Live arrival times are not available: operators do not publish an open vehicle-position feed.',
                    ),
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
