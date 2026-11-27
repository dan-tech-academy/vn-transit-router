import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vn_transit/ui/common.dart';
import 'package:vn_transit/data/geo.dart';
import 'package:vn_transit/data/transit_data.dart';
import 'package:vn_transit/l10n.dart';
import 'package:vn_transit/routing/router.dart';
import 'package:vn_transit/services/geocoder.dart';
import 'package:vn_transit/services/walk_router.dart';
import 'package:vn_transit/ui/itinerary_screen.dart';

void main() {
  late TransitRouter router;
  const benThanh = Geo(10.7725, 106.6980);
  const suoiTien = Geo(10.8665, 106.8030);
  const hoGuom = Geo(21.0287, 105.8524);
  const myDinh = Geo(21.0285, 105.7780);
  // A weekday noon in Vietnam.
  final noon = DateTime.utc(2026, 11, 25, 5);

  setUpAll(() {
    router = TransitRouter(
      TransitData.fromGzip(File('data/transit.json.gz').readAsBytesSync()),
    );
  });
  tearDown(() => appLang = 'vi');

  test('metro only uses nothing but metro', () {
    final its = router.plan(
      benThanh,
      suoiTien,
      departAt: noon,
      modes: const {TransitMode.metro},
    );
    expect(its.where((i) => !i.walkOnly), isNotEmpty);
    for (final it in its) {
      expect(it.rides.every((l) => l.route!.mode == TransitMode.metro), isTrue);
    }
  });

  test('metro only finds nothing where there is no metro', () {
    final its = router.plan(
      const Geo(16.0560, 108.2030),
      const Geo(16.0610, 108.2460),
      departAt: noon,
      modes: const {TransitMode.metro},
    );
    expect(its.where((i) => !i.walkOnly), isEmpty);
  });

  test('preferences rank by walking and transfers', () {
    List<Itinerary> plan(RoutePreference p) =>
        router.plan(hoGuom, myDinh, departAt: noon, preference: p);
    final fast = plan(RoutePreference.fastest);
    final walk = plan(RoutePreference.lessWalking);
    final transfers = plan(RoutePreference.fewerTransfers);
    expect(fast, isNotEmpty);
    expect(walk.first.walkMetres, lessThanOrEqualTo(fast.first.walkMetres));
    expect(transfers.first.transfers, lessThanOrEqualTo(fast.first.transfers));
  });

  test('a later departure time changes which lines run', () {
    final night = DateTime.utc(2026, 11, 25, 19, 30); // 02:30 in Vietnam
    final day = router.plan(benThanh, suoiTien, departAt: noon);
    final late = router.plan(benThanh, suoiTien, departAt: night);
    expect(day.where((i) => !i.walkOnly), isNotEmpty);
    expect(
      late.where((i) => !i.walkOnly).length,
      lessThan(day.where((i) => !i.walkOnly).length),
    );
  });

  test('share text lists every leg in the chosen language', () {
    final it = router
        .plan(benThanh, suoiTien, departAt: noon)
        .firstWhere((i) => !i.walkOnly);
    const from = Place('Chợ Bến Thành', '', benThanh);
    const to = Place('Suối Tiên', '', suoiTien);
    final vi = itineraryShareText(it, from, to, noon);
    expect(vi, contains('Chợ Bến Thành → Suối Tiên'));
    expect(vi, contains('Đi bộ'));
    expect(vi, contains('${it.legs.length}. '));
    // A ride is listed when it is boarded, after the walk and the wait.
    final ride = it.legs.indexWhere((l) => l.kind == LegKind.ride);
    expect(it.legs[ride].waitSeconds, greaterThan(0));
    final before = it.legs
        .take(ride)
        .fold(0, (a, l) => a + l.seconds + l.waitSeconds);
    final boards = noon.add(
      Duration(seconds: before + it.legs[ride].waitSeconds),
    );
    expect(vi, contains('${ride + 1}. ${fmtClock(boards)} '));
    appLang = 'en';
    final en = itineraryShareText(it, from, to, noon);
    expect(en, contains('Walk'));
    expect(en, isNot(contains('Đi bộ')));
  });

  test('walk router decodes a street path and falls back on errors', () async {
    const a = Geo(10.0, 106.0), b = Geo(10.001, 106.001);
    final ok = WalkRouter(
      MockClient((req) async {
        expect(req.url.host, 'routing.openstreetmap.de');
        expect(req.url.path, contains('106.00000,10.00000;106.00100,10.00100'));
        return http.Response(
          '{"code":"Ok","routes":[{"geometry":"_c`|@_cnfS??_ibE_ibE"}]}',
          200,
        );
      }),
    );
    final w = await ok.route(a, b);
    expect(w, isNotNull);
    expect(w!.path.first, a);
    expect(w.path.last, b);
    expect(w.metres, greaterThan(0));

    final down = WalkRouter(MockClient((_) async => http.Response('', 503)));
    expect(await down.route(a, b), isNull);
    final offline = WalkRouter(MockClient((_) async => throw 'no network'));
    expect(await offline.route(a, b), isNull);
  });
}
