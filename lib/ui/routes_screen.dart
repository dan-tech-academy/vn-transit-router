import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../app_state.dart';
import '../data/geo.dart';
import '../data/transit_data.dart';
import 'common.dart';
import 'route_detail_screen.dart';

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  String? _city;
  String _query = '';
  late final Map<String, List<List<TransitRoute>>> _byCity = _group();

  /// Groups the directions of each line, per city.
  Map<String, List<List<TransitRoute>>> _group() {
    // Watching also rebuilds this tab when the language changes.
    final data = context.watch<AppState>().data!;
    final lines = <String, List<TransitRoute>>{};
    for (final r in data.routes) {
      (lines[r.lineKey] ??= []).add(r);
    }
    final out = <String, List<List<TransitRoute>>>{};
    for (final l in lines.values) {
      (out[l.first.city] ??= []).add(l);
    }
    int rank(TransitRoute r) => r.mode == TransitMode.metro ? 0 : 1;
    for (final list in out.values) {
      list.sort((a, b) {
        final c = rank(a.first).compareTo(rank(b.first));
        if (c != 0) return c;
        final na =
            int.tryParse(RegExp(r'\d+').stringMatch(a.first.ref) ?? '') ?? 9999;
        final nb =
            int.tryParse(RegExp(r'\d+').stringMatch(b.first.ref) ?? '') ?? 9999;
        return na != nb ? na.compareTo(nb) : a.first.ref.compareTo(b.first.ref);
      });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cities = _byCity.keys.toList()
      ..sort((a, b) => _byCity[b]!.length.compareTo(_byCity[a]!.length));
    final city = _city ?? cities.first;
    final q = foldVi(_query.trim());
    final lines = _byCity[city]!
        .where(
          (l) =>
              q.isEmpty ||
              foldVi(l.first.ref).contains(q) ||
              l.any(
                (r) =>
                    foldVi(r.title).contains(q) || foldVi(r.name).contains(q),
              ),
        )
        .toList();
    return pageStatusBar(
      context,
      Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  tr('Tra cứu tuyến', 'Browse routes'),
                  style: t.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Material(
                  color: t.colorScheme.surface,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(28),
                  child: TextField(
                    key: const Key('route-query'),
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: tr(
                        'Số tuyến hoặc tên (vd: 19, Bến Thành)',
                        'Line number or name (e.g. 19, Bến Thành)',
                      ),
                      prefixIcon: const Icon(Icons.search),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cities.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ChoiceChip(
                    label: Text('${cities[i]} (${_byCity[cities[i]]!.length})'),
                    selected: cities[i] == city,
                    shape: const StadiumBorder(),
                    onSelected: (_) => setState(() => _city = cities[i]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: lines.isEmpty
                    ? Center(
                        child: Text(
                          tr('Không có tuyến phù hợp.', 'No matching routes.'),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final l = lines[i];
                          final r = l.first;
                          return StubCard(
                            color: modeTint(r.mode),
                            icon: modeIcon(r.mode),
                            label: r.label,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    RouteDetailScreen(route: r, directions: l),
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
                                const SizedBox(height: 4),
                                Text(
                                  '${r.stops.length} ${tr('trạm', 'stops')} · ${fmtDistance(r.dist.last)}'
                                  '${l.length > 1 ? ' · ${l.length} ${tr('chiều', 'directions')}' : ''}',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: t.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
