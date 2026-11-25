import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/geo.dart';
import 'data/transit_data.dart';
import 'l10n.dart';
import 'routing/router.dart';
import 'services/geocoder.dart';
import 'services/walk_router.dart';
import 'ui/common.dart' show tileCacheDir;

class AppState extends ChangeNotifier {
  TransitData? data;
  TransitRouter? router;
  Object? loadError;
  final geocoder = Geocoder();
  final walkRouter = WalkRouter();
  List<Place> recent = [];
  SharedPreferences? _prefs;

  // Settings.
  ThemeMode themeMode = ThemeMode.system;
  String lang = 'vi';
  RoutePreference preference = RoutePreference.fastest;
  bool metroOnly = false;
  bool streetWalking = false;

  // Favourites.
  Place? home;
  Place? work;
  List<Place> saved = [];
  List<(Place, Place)> trips = [];

  // Planner endpoints, shared so other screens can start a search.
  Place? from;
  Place? to;
  int tab = 0;
  int planTick = 0;

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// Opens the planner with these endpoints and runs a search.
  void planWith({Place? from, Place? to}) {
    if (from != null) this.from = from;
    if (to != null) this.to = to;
    tab = 0;
    planTick++;
    notifyListeners();
  }

  void clearPlan() {
    from = to = null;
    notifyListeners();
  }

  void swapEndpoints() {
    final t = from;
    from = to;
    to = t;
    planTick++;
    notifyListeners();
  }

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
      final prefs = _prefs = await SharedPreferences.getInstance();
      List<Place> places(String key) => [
        for (final s in prefs.getStringList(key) ?? const <String>[])
          Place.fromJson(jsonDecode(s) as Map<String, dynamic>),
      ];
      Place? place(String key) {
        final s = prefs.getString(key);
        return s == null
            ? null
            : Place.fromJson(jsonDecode(s) as Map<String, dynamic>);
      }

      try {
        tileCacheDir = '${(await getApplicationSupportDirectory()).path}/tiles';
      } catch (_) {}
      recent = places('recent');
      saved = places('saved');
      home = place('home');
      work = place('work');
      final t = places('trips');
      trips = [for (var i = 0; i + 1 < t.length; i += 2) (t[i], t[i + 1])];
      themeMode = ThemeMode.values[prefs.getInt('theme') ?? 0];
      lang = appLang = prefs.getString('lang') ?? 'vi';
      preference = RoutePreference.values[prefs.getInt('pref') ?? 0];
      metroOnly = prefs.getBool('metroOnly') ?? false;
      streetWalking = prefs.getBool('streetWalking') ?? false;
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
    await _prefs?.setStringList('recent', [
      for (final r in recent) jsonEncode(r.toJson()),
    ]);
  }

  static bool _same(Place a, Place b) =>
      a.name == b.name && distanceBetween(a.geo, b.geo) < 50;

  bool isSaved(Place p) => saved.any((s) => _same(s, p));

  Future<void> toggleSaved(Place p) async {
    if (isSaved(p)) {
      saved.removeWhere((s) => _same(s, p));
    } else {
      saved.insert(0, p);
    }
    notifyListeners();
    await _prefs?.setStringList('saved', [
      for (final r in saved) jsonEncode(r.toJson()),
    ]);
  }

  Future<void> setHome(Place? p) => _setPlace('home', p, (v) => home = v);
  Future<void> setWork(Place? p) => _setPlace('work', p, (v) => work = v);

  Future<void> _setPlace(
    String key,
    Place? p,
    void Function(Place?) set,
  ) async {
    set(p);
    notifyListeners();
    if (p == null) {
      await _prefs?.remove(key);
    } else {
      await _prefs?.setString(key, jsonEncode(p.toJson()));
    }
  }

  bool isTripSaved(Place a, Place b) =>
      trips.any((t) => _same(t.$1, a) && _same(t.$2, b));

  Future<void> toggleTrip(Place a, Place b) async {
    if (isTripSaved(a, b)) {
      trips.removeWhere((t) => _same(t.$1, a) && _same(t.$2, b));
    } else {
      trips.insert(0, (a, b));
    }
    notifyListeners();
    await _prefs?.setStringList('trips', [
      for (final t in trips) ...[
        jsonEncode(t.$1.toJson()),
        jsonEncode(t.$2.toJson()),
      ],
    ]);
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await _prefs?.setInt('theme', m.index);
  }

  Future<void> setLang(String l) async {
    lang = appLang = l;
    notifyListeners();
    await _prefs?.setString('lang', l);
  }

  Future<void> setRouting({
    RoutePreference? preference,
    bool? metroOnly,
    bool? streetWalking,
  }) async {
    this.preference = preference ?? this.preference;
    this.metroOnly = metroOnly ?? this.metroOnly;
    this.streetWalking = streetWalking ?? this.streetWalking;
    planTick++;
    notifyListeners();
    await _prefs?.setInt('pref', this.preference.index);
    await _prefs?.setBool('metroOnly', this.metroOnly);
    await _prefs?.setBool('streetWalking', this.streetWalking);
  }

  /// Stored for the device location; shown translated.
  static const myLocationName = 'Vị trí của tôi';
  static String placeName(Place p) =>
      p.name == myLocationName ? tr('Vị trí của tôi', 'My location') : p.name;

  /// Returns the device location, or throws a user-facing message.
  Future<Geo> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw tr(
        'Hãy bật dịch vụ vị trí (GPS) trên thiết bị.',
        'Turn on location services (GPS) on this device.',
      );
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw tr(
        'Ứng dụng chưa được cấp quyền vị trí.',
        'The app does not have location permission.',
      );
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
