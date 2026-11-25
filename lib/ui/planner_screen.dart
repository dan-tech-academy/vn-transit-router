import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/geo.dart';
import '../data/transit_data.dart';
import '../l10n.dart';
import '../routing/router.dart';
import '../services/geocoder.dart';
import 'common.dart';
import 'itinerary_screen.dart';
import 'place_search_screen.dart';
import 'settings_screen.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  List<Itinerary>? _results;
  DateTime _searchedAt = DateTime.now();

  /// Null means leave now.
  DateTime? _departAt;
  late final AppState _app;
  int _tick = 0;

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

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _tick = _app.planTick;
    _app.addListener(_onApp);
  }

  @override
  void dispose() {
    _app.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    if (_app.planTick == _tick) return;
    _tick = _app.planTick;
    _search();
  }

  void _search() {
    final from = _app.from, to = _app.to;
    if (from == null || to == null || !mounted) return;
    setState(() {
      _searchedAt = _departAt ?? DateTime.now();
      _results = _app.router!.plan(
        from.geo,
        to.geo,
        originName: from.name,
        destName: to.name,
        departAt: _searchedAt,
        preference: _app.preference,
        modes: _app.metroOnly ? const {TransitMode.metro} : null,
      );
    });
  }

  Future<Place?> _choose(String title) => Navigator.of(context).push<Place>(
    MaterialPageRoute(builder: (_) => PlaceSearchScreen(title: title)),
  );

  Future<void> _pick(bool from) async {
    final p = await _choose(
      from
          ? tr('Chọn điểm đi', 'Choose origin')
          : tr('Chọn điểm đến', 'Choose destination'),
    );
    if (p == null) return;
    _app.planWith(from: from ? p : null, to: from ? null : p);
  }

  /// Saved trips keep the "My location" label, not where the user was.
  Future<void> _openTrip(Place a, Place b) async {
    Future<Place> fresh(Place p) async {
      if (p.name != AppState.myLocationName) return p;
      try {
        return Place(p.name, '', await _app.locate());
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
        rethrow;
      }
    }

    try {
      final from = await fresh(a), to = await fresh(b);
      _app.planWith(from: from, to: to);
    } catch (_) {}
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    // A picked time may have passed while the app stayed open.
    final base = _departAt != null && _departAt!.isAfter(now)
        ? _departAt!
        : now;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('depart-now'),
              leading: const Icon(Icons.bolt_rounded),
              title: Text(tr('Đi ngay bây giờ', 'Leave now')),
              onTap: () => Navigator.pop(context, 'now'),
            ),
            ListTile(
              key: const Key('depart-pick'),
              leading: const Icon(Icons.schedule_rounded),
              title: Text(tr('Chọn ngày giờ khởi hành', 'Pick date and time')),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'now') {
      setState(() => _departAt = null);
      _search();
      return;
    }
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null || !mounted) return;
    setState(
      () => _departAt = DateTime(d.year, d.month, d.day, t.hour, t.minute),
    );
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
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
                  const Spacer(),
                  IconButton(
                    key: const Key('settings'),
                    tooltip: tr('Cài đặt', 'Settings'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _endpointsCard(app, scheme),
            ),
            _options(app),
            Expanded(child: _results == null ? _idle(app) : _resultList(app)),
          ],
        ),
      ),
    );
  }

  Widget _options(AppState app) {
    Widget pref(RoutePreference p, String label, String key) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: Key(key),
        label: Text(label),
        selected: app.preference == p,
        onSelected: (_) => app.setRouting(preference: p),
      ),
    );
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              key: const Key('depart'),
              avatar: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(
                _departAt == null
                    ? tr('Đi ngay', 'Leave now')
                    : fmtDateTime(_departAt!),
              ),
              onPressed: _pickTime,
            ),
          ),
          pref(
            RoutePreference.fastest,
            tr('Nhanh nhất', 'Fastest'),
            'pref-fast',
          ),
          pref(
            RoutePreference.lessWalking,
            tr('Ít đi bộ', 'Less walking'),
            'pref-walk',
          ),
          pref(
            RoutePreference.fewerTransfers,
            tr('Ít chuyển tuyến', 'Fewer transfers'),
            'pref-transfers',
          ),
          FilterChip(
            key: const Key('metro-only'),
            label: Text(tr('Chỉ metro', 'Metro only')),
            selected: app.metroOnly,
            onSelected: (v) => app.setRouting(metroOnly: v),
          ),
        ],
      ),
    );
  }

  Widget _endpointsCard(AppState app, ColorScheme scheme) => Card(
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
                _field(
                  app.from,
                  tr('Điểm đi', 'From'),
                  () => _pick(true),
                  const Key('from'),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                _field(
                  app.to,
                  tr('Điểm đến', 'To'),
                  () => _pick(false),
                  const Key('to'),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('swap'),
            tooltip: tr('Đổi chiều', 'Swap'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: app.swapEndpoints,
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
        p == null ? hint : AppState.placeName(p),
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

  /// Home/work shortcut: tap to go there, long-press to change or remove.
  Widget _shortcut(
    String key,
    IconData icon,
    String label,
    Place? place,
    Future<void> Function(Place?) set,
  ) {
    Future<void> assign() async {
      final p = await _choose(label);
      if (p != null) await set(p);
    }

    return Expanded(
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: Key(key),
          dense: true,
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(
            place?.name ?? tr('Chạm để đặt', 'Tap to set'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: place == null ? assign : () => _app.planWith(to: place),
          onLongPress: place == null
              ? null
              : () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(tr('Đổi địa điểm', 'Change place')),
                          onTap: () {
                            Navigator.pop(context);
                            assign();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(tr('Xoá', 'Remove')),
                          onTap: () {
                            Navigator.pop(context);
                            set(null);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _idle(AppState app) {
    final t = Theme.of(context);
    final data = app.data!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Row(
          children: [
            _shortcut(
              'fav-home',
              Icons.home_rounded,
              tr('Nhà', 'Home'),
              app.home,
              app.setHome,
            ),
            const SizedBox(width: 8),
            _shortcut(
              'fav-work',
              Icons.work_rounded,
              tr('Cơ quan', 'Work'),
              app.work,
              app.setWork,
            ),
          ],
        ),
        if (app.trips.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            tr('Lộ trình đã lưu', 'Saved trips'),
            style: t.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final (a, b) in app.trips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: t.colorScheme.surfaceContainer,
                child: ListTile(
                  leading: const Icon(Icons.bookmark_rounded),
                  title: Text(
                    '${AppState.placeName(a)} → ${AppState.placeName(b)}',
                  ),
                  trailing: IconButton(
                    tooltip: tr('Xoá', 'Remove'),
                    icon: const Icon(Icons.close),
                    onPressed: () => app.toggleTrip(a, b),
                  ),
                  onTap: () => _openTrip(a, b),
                ),
              ),
            ),
        ],
        if (app.saved.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            tr('Địa điểm đã lưu', 'Saved places'),
            style: t.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final p in app.saved)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: t.colorScheme.surfaceContainer,
                child: ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: Text(p.name),
                  subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle),
                  trailing: IconButton(
                    tooltip: tr('Xoá', 'Remove'),
                    icon: const Icon(Icons.close),
                    onPressed: () => app.toggleSaved(p),
                  ),
                  onTap: () => app.planWith(to: p),
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(tr('Thử nhanh', 'Quick try'), style: t.textTheme.titleMedium),
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
                onTap: () => app.planWith(from: a, to: b),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Dữ liệu ngoại tuyến: ${data.routes.length} chiều tuyến, '
                '${data.stops.length} trạm từ OpenStreetMap (${data.generated}). '
                'Thời gian và giá vé là ước tính, không phải lịch chạy thực tế.',
            'Offline data: ${data.routes.length} route directions, '
                '${data.stops.length} stops from OpenStreetMap (${data.generated}). '
                'Times and fares are estimates, not real timetables.',
          ),
          style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _resultList(AppState app) {
    final t = Theme.of(context);
    final results = _results!;
    final from = app.from!, to = app.to!;
    final tripSaved = app.isTripSaved(from, to);
    final header = Row(
      children: [
        Expanded(
          child: Text(
            tr(
              '${results.length} lộ trình · khởi hành ${fmtClock(_searchedAt)}',
              '${results.length} options · leaving ${fmtClock(_searchedAt)}',
            ),
            style: t.textTheme.labelLarge?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          key: const Key('clear'),
          visualDensity: VisualDensity.compact,
          tooltip: tr('Xoá tìm kiếm', 'Clear search'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            setState(() => _results = null);
            app.clearPlan();
          },
        ),
        IconButton(
          key: const Key('save-trip'),
          visualDensity: VisualDensity.compact,
          tooltip: tripSaved
              ? tr('Bỏ lưu lộ trình', 'Remove saved trip')
              : tr('Lưu lộ trình', 'Save trip'),
          icon: Icon(
            tripSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          ),
          onPressed: () => app.toggleTrip(from, to),
        ),
      ],
    );
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          children: [
            header,
            Expanded(
              child: Center(
                child: Text(
                  app.metroOnly
                      ? tr(
                          'Không có lộ trình chỉ dùng metro giữa hai điểm này.',
                          'No metro-only trip between these places.',
                        )
                      : tr(
                          'Không tìm thấy lộ trình phù hợp vào giờ này.',
                          'No trip found at this time.',
                        ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length + 2,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) return header;
        if (i == results.length + 1) {
          return Text(
            tr(
              'Thời gian gồm chờ xe ước tính theo tần suất tuyến. Giá vé chỉ để tham khảo.',
              'Times include an estimated wait based on line frequency. Fares are indicative only.',
            ),
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
                from: from,
                to: to,
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
                '${fmtMinutes(l.seconds)}\'',
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
                        tr('Đề xuất', 'Best'),
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
                    tr('Chỉ đi bộ', 'Walk only')
                  else
                    it.transfers == 0
                        ? tr('Đi thẳng', 'Direct')
                        : tr(
                            '${it.transfers} lần chuyển tuyến',
                            '${it.transfers} transfer${it.transfers > 1 ? 's' : ''}',
                          ),
                  tr(
                    'Đi bộ ${fmtDistance(it.walkMetres)}',
                    'Walk ${fmtDistance(it.walkMetres)}',
                  ),
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
