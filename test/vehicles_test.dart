import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_transit/data/transit_data.dart';
import 'package:vn_transit/routing/router.dart';
import 'package:vn_transit/routing/vehicles.dart';

// Three stops 0.01 degrees of latitude apart (about 1112 m).
const _shape = r'_c`|@_c~eSo}@?o}@?';

TransitRoute _route(String hours, {int? headway}) => TransitData.fromJson(
  jsonEncode({
    'generated': 'x',
    'stops': [
      [10.0, 106.0, 'A'],
      [10.01, 106.0, 'B'],
      [10.02, 106.0, 'C'],
    ],
    'routes': [
      {
        'city': 'X',
        'id': 1,
        'ref': '1',
        'name': '',
        'from': '',
        'to': '',
        'mode': 'bus',
        'net': '',
        'op': '',
        'col': '',
        'hw': headway ?? 0,
        'oh': hours,
        'charge': '',
        'stops': [0, 1, 2],
        'dist': [0, 1112, 2224],
        'idx': [0, 1, 2],
        'shape': _shape,
      },
    ],
  }),
).routes.single;

/// A Vietnam-time clock reading on Monday 2026-11-23.
DateTime _at(int h, int m, [int s = 0, int day = 23]) =>
    DateTime.utc(2026, 11, day, h, m, s).subtract(const Duration(hours: 7));

void main() {
  test('routes without a schedule give no estimate', () {
    expect(estimateVehicles(_route(''), _at(8, 0)), isNull);
    expect(estimateVehicles(_route('Mo-Su 05:00-21:00'), _at(8, 0)), isNull);
    expect(estimateVehicles(_route('', headway: 10), _at(8, 0)), isNull);
  });

  test('a vehicle is placed by the time since it left', () {
    final r = _route('Mo-Su 05:00-21:00', headway: 10);
    // Trip: 182 s to B, 20 s stop, 182 s to C => leaves C's time at 404 s.
    expect(stopSeconds(r), [0, 202, 404]);
    final v = estimateVehicles(r, _at(8, 1, 31))!.single; // left at 08:00
    expect(v.nextStop, 1);
    expect(v.secondsToNext, 91);
    expect(v.position.lat, closeTo(10.005, 0.0002));
    expect(v.position.lon, closeTo(106.0, 1e-6));

    final waiting = estimateVehicles(r, _at(8, 3, 10))!.single; // 190 s in
    expect(waiting.nextStop, 1);
    expect(waiting.secondsToNext, 0);
    expect(waiting.position.lat, closeTo(10.01, 1e-6));

    final later = estimateVehicles(r, _at(8, 5))!.single; // 300 s in
    expect(later.nextStop, 2);
    expect(later.position.lat, closeTo(10.0154, 0.0003));

    expect(estimateVehicles(r, _at(8, 7)), isEmpty); // trip over at 404 s
  });

  test('several vehicles run when the headway is shorter than the trip', () {
    final r = _route('Mo-Su 05:00-21:00', headway: 2);
    final v = estimateVehicles(r, _at(8, 5))!;
    expect(v.map((e) => e.nextStop), [1, 1, 2]); // left 08:04, 08:02, 08:00
  });

  test('nothing runs outside the hours or on other days', () {
    final r = _route('Mo-Fr 05:00-21:00', headway: 10);
    expect(estimateVehicles(r, _at(4, 59)), isEmpty);
    expect(estimateVehicles(r, _at(21, 30)), isEmpty);
    expect(estimateVehicles(r, _at(21, 1)), hasLength(1)); // the 21:00 run
    expect(estimateVehicles(r, _at(8, 1, 0, 28)), isEmpty); // Saturday
    expect(nextDeparture(r, _at(4, 0)), 300);
    expect(nextDeparture(r, _at(8, 1)), 490);
    expect(nextDeparture(r, _at(21, 30)), isNull);
  });

  test('fixed departures and runs past midnight are followed', () {
    final fixed = _route('Mo-Fr 07:00,17:15');
    expect(estimateVehicles(fixed, _at(17, 16))!.single.nextStop, 1);
    expect(estimateVehicles(fixed, _at(12, 0)), isEmpty);
    expect(nextDeparture(fixed, _at(12, 0)), 17 * 60 + 15);

    // Hours without a headway on weekdays, one mapped run on Saturday.
    final mixed = _route('Mo-Fr 06:08-06:15; Sa 06:15');
    expect(estimateVehicles(mixed, _at(6, 16)), isNull);
    expect(estimateVehicles(mixed, _at(6, 16, 0, 28))!.single.nextStop, 1);
    expect(nextDeparture(mixed, _at(5, 0, 0, 28)), 375);
    expect(estimateVehicles(mixed, _at(6, 16, 0, 29)), isNull); // Sunday
    final hoursOnly = _route('Mo-Fr 05:00-21:00');
    expect(estimateVehicles(hoursOnly, _at(12, 0, 0, 28)), isNull);

    final night = _route('Mo 22:00-00:30', headway: 30);
    // 00:31 on Tuesday: the 00:30 run that belongs to Monday's hours.
    final v = estimateVehicles(night, _at(0, 31, 0, 24))!.single;
    expect(v.nextStop, 1);
    expect(nextDeparture(night, _at(0, 10, 0, 24)), 30);
    expect(nextDeparture(night, _at(0, 40, 0, 24)), isNull);
    expect(nextDeparture(night, _at(21, 0)), 22 * 60);
  });
}
