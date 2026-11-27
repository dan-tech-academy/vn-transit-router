import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_transit/data/geo.dart';
import 'package:vn_transit/data/transit_data.dart';
import 'package:vn_transit/routing/router.dart';

void main() {
  late TransitData data;
  late TransitRouter router;

  setUpAll(() {
    data = TransitData.fromGzip(File('data/transit.json.gz').readAsBytesSync());
    router = TransitRouter(data);
  });

  void dump(String title, List<Itinerary> its) {
    // ignore: avoid_print
    print('== $title');
    for (final it in its) {
      final parts = it.legs.map(
        (l) => l.kind == LegKind.walk
            ? 'walk ${l.metres}m'
            : '${l.route!.modeLabel} ${l.route!.label} [${l.fromName} -> ${l.toName}, ${l.stopCount} trạm]',
      );
      // ignore: avoid_print
      print('${it.seconds ~/ 60}\' ${it.fare}đ: ${parts.join(' | ')}');
    }
  }

  test('dataset loads', () {
    expect(data.routes.length, greaterThan(800));
    expect(data.stops.length, greaterThan(10000));
    expect(data.routes.where((r) => r.mode == TransitMode.metro).length, 6);
  });

  test('HCMC metro line 1: Bến Thành to Suối Tiên', () {
    final its = router.plan(
      const Geo(10.7725, 106.6980),
      const Geo(10.8795, 106.8140),
    );
    dump('Bến Thành -> Suối Tiên', its);
    expect(
      its.first.rides.any((l) => l.route!.mode == TransitMode.metro),
      isTrue,
    );
    expect(its.first.seconds, lessThan(70 * 60));
  });

  test('Hanoi: Hồ Gươm to Bến xe Mỹ Đình', () {
    final its = router.plan(
      const Geo(21.0287, 105.8524),
      const Geo(21.0285, 105.7780),
    );
    dump('Hồ Gươm -> Mỹ Đình', its);
    expect(its, isNotEmpty);
    expect(its.first.walkOnly, isFalse);
    expect(its.map((i) => i.signature).toSet().length, its.length);
  });

  test('Hanoi metro 2A: Cát Linh to Yên Nghĩa', () {
    final its = router.plan(
      const Geo(21.0283, 105.8275),
      const Geo(20.9530, 105.7470),
    );
    dump('Cát Linh -> Yên Nghĩa', its);
    expect(its.any((i) => i.rides.any((l) => l.route!.ref == 'T2A')), isTrue);
  });

  test('Da Nang: airport to Mỹ Khê', () {
    final its = router.plan(
      const Geo(16.0560, 108.2030),
      const Geo(16.0610, 108.2460),
    );
    dump('Đà Nẵng', its);
    expect(its, isNotEmpty);
  });

  test('short trip offers walking', () {
    final its = router.plan(
      const Geo(10.7725, 106.6980),
      const Geo(10.7760, 106.7010),
    );
    expect(its.any((i) => i.walkOnly), isTrue);
  });

  test('legs are continuous and times add up', () {
    final its = router.plan(
      const Geo(10.8010, 106.6520),
      const Geo(10.7340, 106.7220),
    );
    dump('Tân Bình -> Quận 7', its);
    for (final it in its) {
      expect(
        it.seconds,
        it.legs.fold<int>(0, (a, l) => a + l.seconds + l.waitSeconds),
      );
      for (var i = 1; i < it.legs.length; i++) {
        final a = it.legs[i - 1].path.last, b = it.legs[i].path.first;
        expect(distanceBetween(a, b), lessThan(120));
      }
    }
  });

  test('no transit nearby falls back to walking', () {
    final its = router.plan(const Geo(8.70, 104.90), const Geo(8.71, 104.91));
    expect(its.single.walkOnly, isTrue);
  });

  test('same origin and destination gives one walk with a path', () {
    const p = Geo(10.7725, 106.6980);
    final its = router.plan(p, p);
    expect(its, hasLength(1));
    expect(its.single.walkOnly, isTrue);
    expect(its.single.legs.single.path, isNotEmpty);
  });

  test('different cities give no route instead of a long walk', () {
    final its = router.plan(
      const Geo(10.7725, 106.6980),
      const Geo(16.0614, 108.2470),
    );
    expect(its, isEmpty);
  });

  test('never returns more than maxResults', () {
    final its = router.plan(
      const Geo(10.7725, 106.6980),
      const Geo(10.7830, 106.7000),
    );
    expect(its.length, lessThanOrEqualTo(5));
    expect(its.where((i) => i.walkOnly), hasLength(1));
  });

  test('routes outside their service hours are not used', () {
    const a = Geo(21.0287, 105.8270), b = Geo(20.9530, 105.7470);
    final day = router.plan(a, b, departAt: DateTime.utc(2026, 1, 5, 2));
    final night = router.plan(a, b, departAt: DateTime.utc(2026, 1, 4, 19));
    expect(day.first.rides, isNotEmpty);
    for (final it in night) {
      for (final l in it.rides) {
        expect(l.route!.inServiceAt(DateTime.utc(2026, 1, 4, 19)), isTrue);
      }
    }
  });

  test('opening hours respect weekdays, midnight and Vietnam time', () {
    TransitRoute withHours(String oh) => TransitRoute(
      index: 0,
      osmId: 0,
      ref: '',
      name: '',
      from: '',
      to: '',
      mode: TransitMode.bus,
      network: '',
      operator: '',
      city: '',
      colour: '',
      headwayMin: null,
      openingHours: oh,
      charge: '',
      scheduleSource: '',
      stops: const [],
      dist: const [],
      shapeIdx: const [],
      encodedShape: '',
    );
    // Vietnam local time given as UTC; 2026-01-05 is a Monday.
    DateTime vn(int day, int h, [int m = 0]) =>
        DateTime.utc(2026, 1, day, h, m).subtract(const Duration(hours: 7));
    final weekend = withHours('Fr 19:00-21:00; Sa-Su 05:00-21:00');
    expect(weekend.inServiceAt(vn(5, 20)), isFalse);
    expect(weekend.inServiceAt(vn(9, 20)), isTrue);
    expect(weekend.inServiceAt(vn(10, 12)), isTrue);
    final late = withHours('Mo-Su 05:00-01:00');
    expect(late.inServiceAt(vn(6, 0, 30)), isTrue);
    expect(late.inServiceAt(vn(6, 2)), isFalse);
    expect(withHours('Mo-SU 05:00-21:00').inServiceAt(vn(11, 12)), isTrue);
    final mixed = withHours('Mo-Fr 06:08-06:15; Sa 06:15');
    expect(mixed.inServiceAt(vn(11, 6, 10)), isFalse);
    expect(mixed.inServiceAt(vn(10, 6, 0)), isTrue);
    expect(mixed.inServiceAt(vn(10, 9)), isFalse);
    expect(withHours('Mo-Fr 07:00,17:15').inServiceAt(vn(5, 17)), isTrue);
    final lone = withHours('Mo-Fr 07:10');
    const wait = Duration(minutes: 8);
    expect(lone.inServiceAt(vn(5, 7, 5), wait: wait), isTrue);
    expect(lone.inServiceAt(vn(5, 7, 15), wait: wait), isFalse);
    expect(late.inServiceAt(vn(6, 0, 58), wait: wait), isFalse);
    expect(withHours('unknown').inServiceAt(vn(5, 3)), isTrue);
    expect(withHours('').inServiceAt(vn(5, 3)), isTrue);
  });

  test('routing is fast', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      router.plan(const Geo(21.0287, 105.8524), const Geo(20.9530, 105.7470));
    }
    // ignore: avoid_print
    print('avg plan ms: ${sw.elapsedMilliseconds / 5}');
    expect(sw.elapsedMilliseconds / 5, lessThan(1500));
  });
}
