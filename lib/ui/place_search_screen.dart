import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../app_state.dart';
import '../data/geo.dart';
import '../services/geocoder.dart';
import 'map_pick_screen.dart';

class PlaceSearchScreen extends StatefulWidget {
  final String title;
  const PlaceSearchScreen({super.key, required this.title});

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _controller = TextEditingController();
  bool _searchedOnline = false;
  List<Place> _stops = [];
  List<Place> _online = [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final q = text.trim();
    _seq++;
    setState(() {
      _stops = q.length < 2 ? [] : _matchStops(q);
      _online = [];
      _searchedOnline = false;
      _loading = false;
      _error = null;
    });
  }

  // Nominatim's usage policy forbids search-as-you-type, so the online
  // lookup only runs when the user submits the query.
  void _onSubmitted(String text) {
    final q = text.trim();
    if (q.length < 3) return;
    setState(() {
      _loading = true;
      _searchedOnline = true;
    });
    _searchOnline(q);
  }

  List<Place> _matchStops(String q) {
    final app = context.read<AppState>();
    final data = app.data!;
    final needle = foldVi(q);
    final seen = <String, List<Geo>>{};
    final out = <Place>[];
    for (final s in data.stops) {
      if (s.name.isEmpty || s.routes.isEmpty) continue;
      if (!foldVi(s.name).contains(needle)) continue;
      final city = data.routes[s.routes.first].city;
      // Collapse platforms of one stop, keep same-name stops elsewhere.
      final same = seen[s.name] ??= [];
      if (same.any((g) => distanceBetween(g, s.geo) < 250)) continue;
      same.add(s.geo);
      final lines = {for (final r in s.routes) data.routes[r].label}.take(5);
      out.add(
        Place(
          s.name,
          tr(
            'Trạm · $city · tuyến ${lines.join(', ')}',
            'Stop · $city · lines ${lines.join(', ')}',
          ),
          s.geo,
          isStop: true,
        ),
      );
      if (out.length >= 10) break;
    }
    return out;
  }

  Future<void> _searchOnline(String q) async {
    final app = context.read<AppState>();
    final seq = ++_seq;
    try {
      final res = await app.geocoder.search(q, near: app.lastKnown);
      if (!mounted || seq != _seq) return;
      setState(() {
        _online = res;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _online = [];
        _loading = false;
        _error = tr(
          'Không tìm được địa điểm trực tuyến. Kiểm tra kết nối mạng.',
          'Online place search failed. Check your connection.',
        );
      });
    }
  }

  void _done(Place p) {
    context.read<AppState>().remember(p);
    Navigator.of(context).pop(p);
  }

  Future<void> _useMyLocation() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      final g = await app.locate();
      if (mounted) {
        Navigator.of(context).pop(Place(AppState.myLocationName, '', g));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickOnMap() async {
    final p = await Navigator.of(context)
        .push<Place>(MaterialPageRoute(builder: (_) => const MapPickScreen()));
    if (p != null && mounted) _done(p);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final typing = _controller.text.trim().length >= 2;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('place-query'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          decoration: InputDecoration(
            hintText: widget.title,
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            key: const Key('use-my-location'),
            leading: const Icon(Icons.my_location_rounded),
            title: Text(tr('Vị trí của tôi', 'My location')),
            onTap: _useMyLocation,
          ),
          ListTile(
            key: const Key('pick-on-map'),
            leading: const Icon(Icons.map_rounded),
            title: Text(tr('Chọn trên bản đồ', 'Pick on map')),
            onTap: _pickOnMap,
          ),
          const Divider(height: 1),
          if (!typing) ...[
            if (app.home != null) _tile(app.home!, Icons.home_rounded),
            if (app.work != null) _tile(app.work!, Icons.work_rounded),
            if (app.saved.isNotEmpty) _header(tr('Đã lưu', 'Saved')),
            for (final p in app.saved) _tile(p, Icons.star_rounded),
            if (app.recent.isNotEmpty) _header(tr('Gần đây', 'Recent')),
            for (final p in app.recent) _tile(p, Icons.history_rounded),
          ] else ...[
            if (_stops.isNotEmpty) _header(tr('Trạm dừng', 'Stops')),
            for (final p in _stops) _tile(p, Icons.directions_bus_rounded),
            if (_online.isNotEmpty) _header(tr('Địa điểm', 'Places')),
            for (final p in _online) _tile(p, Icons.place_outlined),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_searchedOnline && _controller.text.trim().length >= 3)
              ListTile(
                key: const Key('search-online'),
                leading: const Icon(Icons.travel_explore),
                title: Text(
                  tr(
                    'Tìm địa danh “${_controller.text.trim()}”',
                    'Search places for “${_controller.text.trim()}”',
                  ),
                ),
                subtitle: Text(
                  tr('Tra trên OpenStreetMap', 'Look up on OpenStreetMap'),
                ),
                onTap: () => _onSubmitted(_controller.text),
              ),
            if (_searchedOnline &&
                !_loading &&
                _stops.isEmpty &&
                _online.isEmpty &&
                _error == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr('Không có kết quả.', 'No results.')),
              ),
          ],
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  Widget _tile(Place p, IconData icon) => ListTile(
    leading: Icon(icon),
    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: p.subtitle.isEmpty
        ? null
        : Text(
            trStopSubtitle(p.subtitle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: IconButton(
      tooltip: tr('Lưu địa điểm', 'Save place'),
      icon: Icon(
        context.watch<AppState>().isSaved(p)
            ? Icons.star_rounded
            : Icons.star_border_rounded,
      ),
      onPressed: () => context.read<AppState>().toggleSaved(p),
    ),
    onTap: () => _done(p),
  );
}
