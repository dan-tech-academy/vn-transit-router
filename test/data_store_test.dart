import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vn_transit/data/data_store.dart';
import 'package:vn_transit/data/transit_data.dart';

Uint8List part(String city, List stops, List<int> routeStops) =>
    Uint8List.fromList(
      gzip.encode(
        utf8.encode(
          jsonEncode({
            'city': city,
            'stops': stops,
            'routes': [
              {
                'city': city,
                'id': 1,
                'ref': city,
                'name': city,
                'from': '',
                'to': '',
                'mode': 'bus',
                'net': '',
                'op': '',
                'col': '',
                'hw': null,
                'oh': '',
                'charge': '',
                'stops': routeStops,
                'dist': [for (var i = 0; i < routeStops.length; i++) i * 500],
                'idx': [for (var i = 0; i < routeStops.length; i++) 0],
                'shape': '',
              },
            ],
          }),
        ),
      ),
    );

void main() {
  late Directory tmp;
  late Map<String, List<int>> server;
  var requests = <String>[];

  http.Client client() => MockClient((req) async {
    requests.add(req.url.path);
    final body = server[req.url.path];
    return body == null
        ? http.Response('', 404)
        : http.Response.bytes(body, 200);
  });

  void publish(String version, Map<String, Uint8List> files) {
    server = {
      for (final e in files.entries) '/v/$version/${e.key}': e.value,
      '/manifest.json': utf8.encode(
        jsonEncode({
          'format': 1,
          'version': version,
          'generated': version,
          'files': [
            for (final e in files.entries)
              {
                'path': 'v/$version/${e.key}',
                'bytes': e.value.length,
                'sha256': sha256.convert(e.value).toString(),
              },
          ],
        }),
      ),
    };
  }

  final a = part(
    'A',
    [
      [10.0, 106.0, 'One', 5],
      [10.01, 106.0, 'Shared', 2],
    ],
    [0, 1],
  );
  final b = part(
    'B',
    [
      [10.01, 106.0, 'Shared', 2],
      [10.02, 106.0, 'Three', 0],
    ],
    [0, 1],
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ghee');
    requests = [];
    publish('1', {'a.gz': a, 'b.gz': b});
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  DataStore store() =>
      DataStore('${tmp.path}/transit', client: client(), baseUrl: 'http://x');

  test(
    'downloads once, then loads from the device without the server',
    () async {
      expect(await store().cached(), isNull);
      expect(await store().update(), isTrue);
      server = {};
      final bundle = (await store().cached())!;
      expect(bundle.version, '1');
      expect(bundle.parts, hasLength(2));
      await expectLater(store().update(), throwsA(isA<HttpException>()));
      expect((await store().cached())!.version, '1');
    },
  );

  test('skips the download when the version is unchanged', () async {
    await store().update();
    requests = [];
    expect(await store().update(), isFalse);
    expect(requests, ['/manifest.json']);
  });

  test('a new version replaces the data and drops unused files', () async {
    await store().update();
    final c = part(
      'C',
      [
        [11.0, 107.0, 'Four', 7],
        [11.01, 107.0, 'Five', 8],
      ],
      [0, 1],
    );
    publish('2', {'a.gz': a, 'c.gz': c});
    requests = [];
    expect(await store().update(), isTrue);
    expect(requests, containsAll(['/manifest.json', '/v/2/c.gz']));
    expect(requests, isNot(contains('/v/2/a.gz')));
    expect((await store().cached())!.version, '2');
    final names = Directory('${tmp.path}/transit')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.endsWith('.gz'));
    expect(names, hasLength(2));
  });

  test('a file that does not match its checksum keeps the old data', () async {
    await store().update();
    publish('2', {'a.gz': a, 'b.gz': b});
    server['/v/2/b.gz'] = [1, 2, 3];
    File('${tmp.path}/transit/${sha256.convert(b)}.gz')
        .deleteSync(); // force a download of b
    await expectLater(store().update(), throwsFormatException);
    expect(await store().cached(), isNull); // b is gone, manifest untouched
    publish('1', {'a.gz': a, 'b.gz': b});
    expect(await store().update(), isTrue);
    expect((await store().cached())!.version, '1');
  });

  test('a damaged stored file is not used', () async {
    await store().update();
    File('${tmp.path}/transit/${sha256.convert(a)}.gz').writeAsBytesSync([0]);
    expect(await store().cached(), isNull);
    expect(await store().update(), isTrue);
    expect(await store().cached(), isNotNull);
  });

  test('stops shared by two city files are merged', () {
    final data = TransitData.fromParts('g', [a, b]);
    expect(data.stops.map((s) => s.name), ['Three', 'Shared', 'One']);
    expect(data.routes[0].stops, [2, 1]);
    expect(data.routes[1].stops, [1, 0]);
    expect(data.stops[1].routes, [0, 1]);
  });

  test('a bad update leaves intact stored data in use', () async {
    await store().update();
    final c = part(
      'C',
      [
        [11.0, 107.0, 'Four', 7],
        [11.01, 107.0, 'Five', 8],
      ],
      [0, 1],
    );
    publish('2', {'a.gz': a, 'c.gz': c});
    server['/v/2/c.gz'] = [1, 2, 3];
    await expectLater(store().update(), throwsFormatException);
    final bundle = (await store().cached())!;
    expect(bundle.version, '1');
    expect(bundle.parts, hasLength(2));
  });

  test('published files rebuild the full dataset', () {
    final m = jsonDecode(File('dist/data/manifest.json').readAsStringSync());
    final parts = [
      for (final f in m['files'] as List)
        File('dist/data/${f['path']}').readAsBytesSync(),
    ];
    final split = TransitData.fromParts(m['generated'] as String, parts);
    final full = TransitData.fromGzip(
      File('data/transit.json.gz').readAsBytesSync(),
    );
    String key(TransitData d, TransitRoute r) =>
        '${r.osmId}|${r.city}|${r.stops.map((s) => '${d.stops[s].lat},${d.stops[s].lon},${d.stops[s].name}').join(';')}';
    expect(
      split.routes.map((r) => key(split, r)).toList()..sort(),
      full.routes.map((r) => key(full, r)).toList()..sort(),
    );
    final used = {for (final r in full.routes) ...r.stops}.toList()..sort();
    expect(split.stops.map((s) => '${s.lat},${s.lon},${s.name}').toList(), [
      for (final s in used)
        '${full.stops[s].lat},${full.stops[s].lon},${full.stops[s].name}',
    ]);
  });
}
