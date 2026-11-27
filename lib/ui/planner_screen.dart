import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
import 'stop_detail_screen.dart';

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
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  static const _sheetSize = 0.46;
  static const _sheetMin = 0.14;

  /// Stops drawn around the map centre while no trip is shown.
  List<Stop> _stops = const [];

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
    final shown = _results!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Bring the sheet back so the trip on the map is not covered.
      final h = _map.camera.nonRotatedSize.height;
      final top = MediaQuery.paddingOf(context).top + 250;
      // On short screens the sheet drops lower to leave the trip some map.
      // With no trip to show the sheet stays up so its message is seen.
      final sheet = shown.isEmpty
          ? _sheetSize
          : ((h - top - 140) / h).clamp(_sheetMin, _sheetSize);
      if (_sheet.isAttached) {
        _sheet.reset();
        if (sheet < _sheetSize) {
          // After the reset has scrolled the list back to the top.
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted || !_sheet.isAttached) return;
            _sheet.animateTo(
              sheet,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          });
        }
      }
      if (shown.isEmpty) return;
      final pts = [for (final l in shown.first.legs) ...l.path.map(ll)];
      if (pts.isEmpty) return;
      if (pts.every((p) => p == pts.first)) {
        _map.move(pts.first, 16);
        return;
      }
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: fitPadding(h, top, h * sheet + 16),
        ),
      );
    });
  }

  void _showStops(LatLng c) => setState(
    () => _stops = [
      for (final (s, _) in _app.data!.stopsNear(
        Geo(c.latitude, c.longitude),
        1500,
        limit: 60,
      ))
        s,
    ],
  );

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
    final data = app.data!;
    final shown = _results?.isNotEmpty == true ? _results!.first : null;
    return Scaffold(
      body: Stack(
        children: [
          mapStatusBar,
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: ll(app.lastKnown ?? const Geo(10.7725, 106.6980)),
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () => _showStops(_map.camera.center),
              onMapEvent: (e) {
                if (e is MapEventMoveEnd ||
                    e is MapEventFlingAnimationEnd ||
                    e is MapEventDoubleTapZoomEnd) {
                  _showStops(e.camera.center);
                }
              },
            ),
            children: [
              const OsmTileLayer(),
              if (shown != null) PolylineLayer(polylines: legPolylines(shown)),
              MarkerLayer(
                markers: [
                  if (shown == null)
                    for (final s in _stops)
                      dotMarker(
                        s.geo,
                        s.routes.isEmpty
                            ? walkColor
                            : modeColor(data.routes[s.routes.first]),
                        label: s.name,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StopDetailScreen(stop: s),
                          ),
                        ),
                      ),
                  if (app.from != null)
                    pinMarker(app.from!.geo, originColor, Icons.trip_origin),
                  if (app.to != null)
                    pinMarker(app.to!.geo, destColor, Icons.location_on),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _endpointsCard(app, scheme),
                ),
                _options(app),
              ],
            ),
          ),
          mapSheet(
            context,
            controller: _sheet,
            initial: _sheetSize,
            min: _sheetMin,
            max: 0.7,
            children: (_) => _results == null ? _idle(app) : _resultList(app),
          ),
        ],
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

  Widget _endpointsCard(AppState app, ColorScheme scheme) => Material(
    color: scheme.surface,
    elevation: 4,
    borderRadius: BorderRadius.circular(24),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFAFE632),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'G',
              style: TextStyle(
                color: Color(0xFF12422C),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
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
                  tr('Đi đâu?', 'Where to?'),
                  () => _pick(false),
                  const Key('to'),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                key: const Key('settings'),
                tooltip: tr('Cài đặt', 'Settings'),
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
        ],
      ),
    ),
  );

  Widget _field(Place? p, String hint, VoidCallback onTap, Key key) => InkWell(
    key: key,
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 44,
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

  List<Widget> _idle(AppState app) {
    final t = Theme.of(context);
    final data = app.data!;
    return [
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
                subtitle: p.subtitle.isEmpty
                    ? null
                    : Text(trStopSubtitle(p.subtitle)),
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
    ];
  }

  List<Widget> _resultList(AppState app) {
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
              '${results.length} option${results.length == 1 ? '' : 's'} · leaving ${fmtClock(_searchedAt)}',
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
            _showStops(_map.camera.center);
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
    return [
      header,
      if (results.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
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
        )
      else ...[
        for (final (i, it) in results.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ItineraryCard(
              key: Key('itinerary-$i'),
              itinerary: it,
              best: i == 0,
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
            ),
          ),
        Text(
          tr(
            'Thời gian gồm chờ xe ước tính theo tần suất tuyến. Giá vé chỉ để tham khảo.',
            'Times include an estimated wait based on line frequency. Fares are indicative only.',
          ),
          style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
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
              Icon(
                Icons.directions_walk_rounded,
                size: 18,
                color: walkInk(context),
              ),
              Text(
                '${fmtMinutes(l.seconds)}\'',
                style: TextStyle(color: walkInk(context), fontSize: 13),
              ),
            ],
          ),
        );
      } else {
        chips.add(LineBadge(l.route!));
      }
    }
    final lead = it.rides.isEmpty ? null : it.rides.first.route!;
    final stub = lead == null ? walkColor : modeTint(lead.mode);
    final paper = t.colorScheme.surfaceContainerLow;
    // A ticket: coloured stub for the first line, perforated edge, details.
    return Material(
      color: paper,
      elevation: best ? 3 : 1,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                color: stub,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      lead == null
                          ? Icons.directions_walk_rounded
                          : modeIcon(lead.mode),
                      color: Colors.white,
                      size: 26,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lead?.label ?? tr('Đi bộ', 'Walk'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: const Size(8, double.infinity),
                painter: _Perforation(stub, paper),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _Perforation extends CustomPainter {
  final Color stub;
  final Color paper;
  const _Perforation(this.stub, this.paper);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width / 2, size.height),
      Paint()..color = stub,
    );
    final hole = Paint()..color = paper;
    for (var y = 6.0; y < size.height; y += 12) {
      canvas.drawCircle(Offset(size.width / 2, y), 4, hole);
    }
  }

  @override
  bool shouldRepaint(_Perforation old) =>
      old.stub != stub || old.paper != paper;
}
