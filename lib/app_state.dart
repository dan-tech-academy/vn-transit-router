import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/geo.dart';
import 'data/transit_data.dart';
import 'routing/router.dart';
import 'services/geocoder.dart';

class AppState extends ChangeNotifier {
  TransitData? data;
  TransitRouter? router;
  Object? loadError;
  final geocoder = Geocoder();
  List<Place> recent = [];
  Geo? lastKnown;

  static const defaultCenter = Geo(10.7725, 106.6980); // Chợ Bến Thành

  bool get ready => router != null;

  Future<void> load() async {
    try {
      final bytes = (await rootBundle.load('assets/data/transit.json.gz'))
          .buffer
          .asUint8List();
      final r = await Isolate.run(
        () => TransitRouter(TransitData.fromGzip(bytes)),
      );
      router = r;
      data = r.data;
      final prefs = await SharedPreferences.getInstance();
      recent = [
        for (final s in prefs.getStringList('recent') ?? const <String>[])
          Place.fromJson(jsonDecode(s) as Map<String, dynamic>),
      ];
    } catch (e) {
      loadError = e;
    }
    notifyListeners();
  }

  Future<void> remember(Place p) async {
    if (p.name == myLocationName) return;
    recent.removeWhere(
      (r) =>
          r.name == p.name &&
          r.subtitle == p.subtitle &&
          distanceBetween(r.geo, p.geo) < 50,
    );
    recent.insert(0, p);
    if (recent.length > 8) recent = recent.sublist(0, 8);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent', [
      for (final r in recent) jsonEncode(r.toJson()),
    ]);
  }

  static const myLocationName = 'Vị trí của tôi';

  /// Returns the device location, or throws a user-facing message.
  Future<Geo> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Hãy bật dịch vụ vị trí (GPS) trên thiết bị.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw 'Ứng dụng chưa được cấp quyền vị trí.';
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    lastKnown = Geo(pos.latitude, pos.longitude);
    return lastKnown!;
  }
}
