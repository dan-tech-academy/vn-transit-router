import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/geo.dart';
import '../routing/router.dart';
import '../services/geocoder.dart';
import 'common.dart';
import 'itinerary_screen.dart';
import 'place_search_screen.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  Place? _from;
  Place? _to;
  List<Itinerary>? _results;
  DateTime _searchedAt = DateTime.now();

  static const _samples = [
    (
      'TP.HCM: Chợ Bến Thành → Suối Tiên',
      Place('Chợ Bến Thành', 'TP. Hồ Chí Minh', Geo(10.7725, 106.6980)),
      Place('Khu du lịch Suối Tiên', 'TP. Thủ Đức', Geo(10.8665, 106.8030)),
    ),
    (
      'Hà Nội: Hồ Gươm → Bến xe Mỹ Đình',
      Place('Hồ Gươm', 'Hoàn Kiếm, Hà Nội', Geo(21.0287, 105.8524)),
      Place('Bến xe Mỹ Đình', 'Nam Từ Liêm, Hà Nội', Geo(21.0285, 105.7780)),
    ),
    (
      'Hà Nội: Ga Cát Linh → Hà Đông',
      Place('Ga Cát Linh', 'Đống Đa, Hà Nội', Geo(21.0283, 105.8275)),
      Place('Ga Hà Đông', 'Hà Đông, Hà Nội', Geo(20.9710, 105.7790)),
    ),
    (
      'Đà Nẵng: Sân bay → Biển Mỹ Khê',
      Place('Sân bay Đà Nẵng', 'Hải Châu, Đà Nẵng', Geo(16.0560, 108.2030)),
      Place('Biển Mỹ Khê', 'Sơn Trà, Đà Nẵng', Geo(16.0610, 108.2460)),
    ),
  ];

  void _search() {
    final app = context.read<AppState>();
    if (_from == null || _to == null) return;
    setState(() {
      _searchedAt = DateTime.now();
      _results = app.router!.plan(
        _from!.geo,
        _to!.geo,
        originName: _from!.name,
        destName: _to!.name,
        departAt: _searchedAt,
      );
    });
  }

  Future<void> _pick(bool from) async {
    final p = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) =>
            PlaceSearchScreen(title: from ? 'Chọn điểm đi' : 'Chọn điểm đến'),
      ),
    );
    if (p == null || !mounted) return;
    setState(() => from ? _from = p : _to = p);
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.alt_route_rounded,
                    color: scheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Lộ Trình Việt',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _endpointsCard(scheme),
            ),
            Expanded(child: _results == null ? _idle() : _resultList()),
          ],
        ),
      ),
    );
  }

  Widget _endpointsCard(ColorScheme scheme) => Card(
    color: scheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Column(
            children: [
              Icon(Icons.trip_origin, size: 16, color: scheme.primary),
              Container(width: 2, height: 26, color: scheme.outlineVariant),
              Icon(Icons.location_on, size: 18, color: scheme.error),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                _field(_from, 'Điểm đi', () => _pick(true), const Key('from')),
                Divider(height: 1, color: scheme.outlineVariant),
                _field(_to, 'Điểm đến', () => _pick(false), const Key('to')),
              ],
            ),
          ),
          IconButton(
            key: const Key('swap'),
            tooltip: 'Đổi chiều',
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () {
              setState(() {
                final t = _from;
                _from = _to;
                _to = t;
              });
              _search();
            },
          ),
        ],
      ),
    ),
  );

  Widget _field(Place? p, String hint, VoidCallback onTap, Key key) => InkWell(
    key: key,
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 46,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        p?.name ?? hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          fontWeight: p == null ? FontWeight.w400 : FontWeight.w600,
          color: p == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        ),
      ),
    ),
  );

  Widget _idle() {
    final t = Theme.of(context);
    final data = context.read<AppState>().data!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Thử nhanh', style: t.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (label, a, b) in _samples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              color: t.colorScheme.surfaceContainer,
              child: ListTile(
                leading: const Icon(Icons.bolt_rounded),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    _from = a;
                    _to = b;
                  });
                  _search();
                },
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Dữ liệu ngoại tuyến: ${data.routes.length} chiều tuyến, '
          '${data.stops.length} trạm từ OpenStreetMap (${data.generated}). '
          'Thời gian và giá vé là ước tính, không phải lịch chạy thực tế.',
          style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _resultList() {
    final t = Theme.of(context);
    final results = _results!;
    if (results.isEmpty) {
      return const Center(
        child: Text('Không tìm thấy lộ trình phù hợp vào giờ này.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: results.length + 2,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            '${results.length} lộ trình · khởi hành ${fmtClock(_searchedAt)}',
            style: t.textTheme.labelLarge?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          );
        }
        if (i == results.length + 1) {
          return Text(
            'Thời gian gồm chờ xe ước tính theo tần suất tuyến. Giá vé chỉ để tham khảo.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          );
        }
        final it = results[i - 1];
        return ItineraryCard(
          key: Key('itinerary-${i - 1}'),
          itinerary: it,
          best: i == 1,
          departAt: _searchedAt,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ItineraryScreen(
                itinerary: it,
                from: _from!,
                to: _to!,
                departAt: _searchedAt,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ItineraryCard extends StatelessWidget {
  final Itinerary itinerary;
  final bool best;
  final DateTime departAt;
  final VoidCallback onTap;
  const ItineraryCard({
    super.key,
    required this.itinerary,
    required this.best,
    required this.departAt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final it = itinerary;
    final arrive = departAt.add(Duration(seconds: it.seconds));
    final chips = <Widget>[];
    for (final l in it.legs) {
      if (chips.isNotEmpty) {
        chips.add(
          Icon(
            Icons.chevron_right,
            size: 16,
            color: t.colorScheme.onSurfaceVariant,
          ),
        );
      }
      if (l.kind == LegKind.walk) {
        chips.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.directions_walk_rounded,
                size: 18,
                color: walkColor,
              ),
              Text(
                '${(l.seconds / 60).round()}\'',
                style: const TextStyle(color: walkColor, fontSize: 13),
              ),
            ],
          ),
        );
      } else {
        chips.add(LineBadge(l.route!));
      }
    }
    return Card(
      color: t.colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: best
            ? BorderSide(color: t.colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtDuration(it.seconds),
                    style: t.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${fmtClock(departAt)} – ${fmtClock(arrive)}',
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (best)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: t.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Đề xuất',
                        style: t.textTheme.labelSmall?.copyWith(
                          color: t.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 2,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: chips,
              ),
              const SizedBox(height: 10),
              Text(
                [
                  if (it.walkOnly)
                    'Chỉ đi bộ'
                  else
                    it.transfers == 0
                        ? 'Đi thẳng'
                        : '${it.transfers} lần chuyển tuyến',
                  'Đi bộ ${fmtDistance(it.walkMetres)}',
                  if (it.fare > 0) '~${fmtMoney(it.fare)}',
                ].join(' · '),
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
