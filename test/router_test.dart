import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_transit/data/geo.dart';
import 'package:vn_transit/data/transit_data.dart';
import 'package:vn_transit/routing/router.dart';

void main() {
  late TransitData data;
  late TransitRouter router;

  setUpAll(() {
    data = TransitData.fromGzip(
      File('assets/data/transit.json.gz').readAsBytesSync(),
    );
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
