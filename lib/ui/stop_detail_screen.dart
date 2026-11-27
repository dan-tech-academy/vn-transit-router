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
      body: Stack(
        children: [
          mapStatusBar,
          FlutterMap(
            options: MapOptions(
              initialCameraFit: fitPoint(context, stop.geo, 0.5, 17),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              const OsmTileLayer(),
              MarkerLayer(
                markers: [pinMarker(stop.geo, color, Icons.location_on)],
              ),
            ],
          ),
          MapTopBar(
            title: Text(
              stop.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                key: const Key('save-stop'),
                tooltip: saved
                    ? tr('Bỏ lưu', 'Remove from saved')
                    : tr('Lưu địa điểm', 'Save place'),
                icon: Icon(
                  saved ? Icons.star_rounded : Icons.star_border_rounded,
                ),
                onPressed: () => app.toggleSaved(place),
              ),
              const SizedBox(width: 4),
            ],
          ),
          mapSheet(
            context,
            initial: 0.5,
            min: 0.2,
            max: 0.85,
            children: (context) => [
              Text(
                stop.displayName,
                style: t.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                [
                  if (cities.isNotEmpty) cities,
                  tr(
                    '${routes.length} chiều tuyến đi qua trạm này',
                    '${routes.length} route directions serve this stop',
                  ),
                ].join(' · '),
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
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
              const SizedBox(height: 16),
              for (final r in routes)
                StubCard(
                  color: modeTint(r.mode),
                  icon: modeIcon(r.mode),
                  label: r.label,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RouteDetailScreen(route: r),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (r.headwayMin != null ||
                          r.openingHours.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (r.headwayMin != null)
                              tr(
                                '${r.headwayMin} phút/chuyến',
                                'every ${r.headwayMin} min',
                              ),
                            if (r.openingHours.isNotEmpty) r.openingHours,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
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
        ],
      ),
    );
  }
}
