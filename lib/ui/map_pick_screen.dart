import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/geocoder.dart';
import 'common.dart';

class MapPickScreen extends StatefulWidget {
  const MapPickScreen({super.key});

  @override
  State<MapPickScreen> createState() => _MapPickScreenState();
}

class _MapPickScreenState extends State<MapPickScreen> {
  final _map = MapController();
  bool _busy = false;

  Future<void> _confirm() async {
    final app = context.read<AppState>();
    final g = geoOf(_map.camera.center);
    setState(() => _busy = true);
    Place? p;
    try {
      p = await app.geocoder.reverse(g);
    } catch (_) {}
    p ??= Place(
      'Điểm đã chọn',
      '${g.lat.toStringAsFixed(5)}, ${g.lon.toStringAsFixed(5)}',
      g,
    );
    if (mounted) Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final start =
        app.lastKnown ??
        (app.recent.isNotEmpty ? app.recent.first.geo : AppState.defaultCenter);
    return Scaffold(
      appBar: AppBar(title: const Text('Chọn trên bản đồ')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: ll(start),
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: const [OsmTileLayer(), OsmAttribution()],
          ),
          const IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(bottom: 44),
              child: Icon(
                Icons.location_on,
                size: 48,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: FilledButton.icon(
                key: const Key('confirm-pick'),
                onPressed: _busy ? null : _confirm,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Chọn vị trí này'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
