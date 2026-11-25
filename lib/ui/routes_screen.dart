import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final data = context.read<AppState>().data!;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Tra cứu tuyến')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('route-query'),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Số tuyến hoặc tên (vd: 19, Bến Thành)',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
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
                onSelected: (_) => setState(() => _city = cities[i]),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('Không có tuyến phù hợp.'))
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final l = lines[i];
                      final r = l.first;
                      return ListTile(
                        leading: SizedBox(
                          width: 84,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: LineBadge(r, large: true),
                          ),
                        ),
                        title: Text(
                          r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${r.modeLabel} · ${r.stops.length} trạm · ${fmtDistance(r.dist.last)}'
                          '${l.length > 1 ? ' · ${l.length} chiều' : ''}',
                          style: t.textTheme.bodySmall,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RouteDetailScreen(route: r, directions: l),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
