import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_transit/data/geo.dart';
import 'package:vn_transit/data/transit_data.dart';
import 'package:vn_transit/l10n.dart';
import 'package:vn_transit/routing/router.dart';

Map<String, dynamic> _route(
  String ref,
  List<int> stops,
  List<int> dist,
  int hw,
  String shape,
) => {
  'city': 'X',
  'id': 1,
  'ref': ref,
  'name': '',
  'from': '',
  'to': '',
  'mode': 'bus',
  'net': '',
  'op': '',
  'col': '',
  'hw': hw,
  'oh': '',
  'charge': '',
  'stops': stops,
  'dist': dist,
  'idx': [for (var i = 0; i < stops.length; i++) i],
  'shape': shape,
};

void main() {
  tearDown(() => appLang = 'vi');
  saturdayTests();

  test('less walking keeps a slower line that stops at the door', () {
    // Line S stops at both ends but runs hourly; line F is frequent and
    // needs about 400 m on foot at each end.
    final data = TransitData.fromJson(
      jsonEncode({
        'stops': [
          [10.0, 106.0, 'S1'],
          [10.0, 106.1, 'S2'],
          [10.003, 106.0, 'F1'],
          [10.003, 106.1, 'F2'],
        ],
        'routes': [
          _route('S', [0, 1], [0, 11000], 60, r'_c`|@_c~eS?_pR'),
          _route('F', [2, 3], [0, 11000], 4, r'wu`|@_c~eS?_pR'),
        ],
      }),
    );
    final router = TransitRouter(data);
    const a = Geo(10.0, 106.0), b = Geo(10.0, 106.1);
    final fast = router.plan(a, b).first;
    final easy = router
        .plan(a, b, preference: RoutePreference.lessWalking)
        .first;
    expect(fast.rides.single.route!.ref, 'F');
    expect(easy.rides.single.route!.ref, 'S');
    expect(easy.walkMetres, lessThan(fast.walkMetres));
  });

  group('real data', () {
    late TransitRouter router;
    setUpAll(() {
      router = TransitRouter(
        TransitData.fromGzip(File('data/transit.json.gz').readAsBytesSync()),
      );
    });

    test('a line with fixed departures is boarded after the bus arrives', () {
      // 61-39 leaves Tòa nhà Becamex at 17:15 on weekdays.
      const cayMe = Geo(10.963617, 106.671498);
      const hungVuong = Geo(11.035222, 106.678774);
      final at = DateTime.utc(2026, 11, 25, 10); // Wed 17:00 in Vietnam
      final its = router.plan(cayMe, hungVuong, departAt: at);
      final ride = its
          .expand((i) => i.legs)
          .where((l) => l.kind == LegKind.ride && l.route!.ref == '61-39')
          .where((l) => l.route!.departuresOn(at) != null);
      expect(ride, isNotEmpty);
      for (final it in its) {
        var t = 0;
        for (final l in it.legs) {
          t += l.waitSeconds;
          if (l.kind == LegKind.ride && l.route!.departuresOn(at) != null) {
            // Boards no earlier than 17:15 plus the run to this stop.
            expect(t, greaterThanOrEqualTo(15 * 60));
          }
          t += l.seconds;
        }
      }
      // Two hours earlier the bus is more than an hour away.
      final early = router.plan(
        cayMe,
        hungVuong,
        departAt: at.subtract(const Duration(hours: 2)),
      );
      expect(
        early
            .expand((i) => i.rides)
            .where((l) => l.route!.departuresOn(at) != null),
        isEmpty,
      );
    });

    test('street walks keep a fixed departure at its time', () {
      const cayMe = Geo(10.963617, 106.671498);
      const hungVuong = Geo(11.035222, 106.678774);
      final at = DateTime.utc(2026, 11, 25, 10);
      final it = router
          .plan(cayMe, hungVuong, departAt: at)
          .firstWhere(
            (i) =>
                i.legs.first.kind == LegKind.walk &&
                i.legs[1].route!.departuresOn(at) != null,
          );
      Leg slower(Leg l, int by) => l.kind == LegKind.walk
          ? l.rewalk(l.path, l.metres, l.seconds + by)
          : l;
      final wait = it.legs[1].waitSeconds;
      final late = withWalks(it.legs, [
        slower(it.legs.first, wait),
        ...it.legs.skip(1),
      ], at)!;
      expect(late[1].waitSeconds, 0);
      expect(
        withWalks(it.legs, [
          slower(it.legs.first, wait + 60),
          ...it.legs.skip(1),
        ], at),
        isNull,
      );
    });

    test('HCMC metro line 1 does not run at night', () {
      const benThanh = Geo(10.7725, 106.6980);
      const suoiTien = Geo(10.8665, 106.8030);
      final night = DateTime.utc(2026, 11, 24, 19, 30); // 02:30 in Vietnam
      final its = router.plan(benThanh, suoiTien, departAt: night);
      expect(
        its.expand((i) => i.rides).where((l) => l.route!.ref == 'L1'),
        isEmpty,
      );
    });
  });

  test('saved stop descriptions follow the language', () {
    appLang = 'en';
    expect(
      trStopSubtitle('Trạm · Hà Nội · tuyến 01, 02'),
      'Stop · Hà Nội · lines 01, 02',
    );
    expect(trStopSubtitle('Hoàn Kiếm, Hà Nội'), 'Hoàn Kiếm, Hà Nội');
    appLang = 'vi';
    expect(
      trStopSubtitle('Stop · Hà Nội · lines 01'),
      'Trạm · Hà Nội · tuyến 01',
    );
  });
}

void saturdayTests() {
  group('Saturday departures on lines with weekday ranges', () {
    late TransitData data;
    late TransitRouter router;
    setUpAll(() {
      data = TransitData.fromGzip(
        File('data/transit.json.gz').readAsBytesSync(),
      );
      router = TransitRouter(data);
    });

    test('61-38 and 61-73 are boarded at their Saturday departure', () {
      final lines = data.routes
          .where((r) => r.ref == '61-38' || r.ref == '61-73')
          .toList();
      expect(lines, hasLength(4));
      // 61-38: Sa 06:15 and Sa 11:20; 61-73: Sa 06:17 and Sa 11:10.
      expect(
        {
          for (final r in lines)
            ...r.departuresOn(DateTime.utc(2026, 11, 27, 17))!,
        },
        {375, 680, 377, 670},
      );
      var boarded = 0;
      for (final r in lines) {
        final sat = DateTime.utc(2026, 11, 27, 17); // Sat 00:00 in Vietnam
        final dep = r.departuresOn(sat)!.single;
        expect(r.departuresOn(sat.subtract(const Duration(days: 1))), isNull);
        expect(r.departuresOn(sat.add(const Duration(days: 1))), isEmpty);
        const from = 3;
        final to = r.stops.length - 3;
        Iterable<(Itinerary, Leg)> rides(int minutesBefore) sync* {
          final its = router.plan(
            data.stops[r.stops[from]].geo,
            data.stops[r.stops[to]].geo,
            departAt: sat.add(Duration(minutes: dep - minutesBefore)),
          );
          for (final it in its) {
            for (final l in it.rides) {
              if (l.route!.index == r.index) yield (it, l);
            }
          }
        }

        final found = rides(20).toList();
        // Other lines can beat this one, so it need not appear every time.
        boarded += found.length;
        for (final (it, leg) in found) {
          var t = 0;
          for (final l in it.legs) {
            t += l.waitSeconds;
            if (identical(l, leg)) break;
            t += l.seconds;
          }
          expect(t, 20 * 60 + stopSeconds(r)[leg.fromPos]);
        }
        // Once the only vehicle has passed, the line is not offered.
        expect(rides(-120), isEmpty, reason: '${r.ref} ${r.name}');
      }
      expect(boarded, greaterThan(0));
    });
  });
}
