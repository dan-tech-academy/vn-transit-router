import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Route data downloaded from the server and kept on the device.
///
/// The server holds `manifest.json`, which lists one gzip file per city with
/// its size and SHA-256. Files are stored under their hash, and the manifest
/// is written last, so a download that stops half way leaves the previous
/// data in place.
class DataStore {
  static const defaultBaseUrl = String.fromEnvironment(
    'GHEE_DATA_URL',
    defaultValue: 'https://ghee-data.dantech.app',
  );
  static const _format = 1;

  final Directory dir;
  final String baseUrl;
  final http.Client _client;

  DataStore(String path, {http.Client? client, this.baseUrl = defaultBaseUrl})
    : dir = Directory(path),
      _client = client ?? http.Client();

  File get _manifestFile => File('${dir.path}/manifest.json');
  File _file(String sha) => File('${dir.path}/$sha.gz');

  /// The stored data, or null when there is none or a file is damaged.
  Future<DataBundle?> cached() async {
    try {
      final manifest = _Manifest.parse(await _manifestFile.readAsString());
      final parts = <Uint8List>[];
      for (final f in manifest.files) {
        final bytes = await _file(f.sha256).readAsBytes();
        if (sha256.convert(bytes).toString() != f.sha256) return null;
        parts.add(bytes);
      }
      return DataBundle(manifest.version, manifest.generated, parts);
    } catch (_) {
      return null;
    }
  }

  /// Downloads the server's data when it differs from what is stored.
  /// Returns whether new data was stored; throws when the server cannot be
  /// reached or sends a file that does not match the manifest.
  Future<bool> update() async {
    final text = utf8.decode(await _get('manifest.json'));
    final manifest = _Manifest.parse(text);
    final have = await cached();
    if (have != null && have.version == manifest.version) return false;
    await dir.create(recursive: true);
    await Future.wait([
      for (final f in manifest.files)
        () async {
          final target = _file(f.sha256);
          if (await target.exists() &&
              sha256.convert(await target.readAsBytes()).toString() ==
                  f.sha256) {
            return;
          }
          final bytes = await _get(f.path);
          if (bytes.length != f.bytes ||
              sha256.convert(bytes).toString() != f.sha256) {
            throw FormatException('Checksum mismatch for ${f.path}');
          }
          await _replace(target, bytes);
        }(),
    ]);
    await _replace(_manifestFile, utf8.encode(text));
    final keep = {for (final f in manifest.files) '${f.sha256}.gz'};
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.endsWith('.gz') && !keep.contains(name)) {
        await e.delete();
      }
    }
    return true;
  }

  Future<Uint8List> _get(String path) async {
    final res = await _client
        .get(Uri.parse('$baseUrl/$path'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} for $path');
    }
    return res.bodyBytes;
  }

  Future<void> _replace(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }
}

class DataBundle {
  final String version;
  final String generated;

  /// One gzip file per city.
  final List<Uint8List> parts;
  DataBundle(this.version, this.generated, this.parts);
}

class _ManifestFile {
  final String path;
  final String sha256;
  final int bytes;
  _ManifestFile(this.path, this.sha256, this.bytes);
}

class _Manifest {
  final String version;
  final String generated;
  final List<_ManifestFile> files;
  _Manifest(this.version, this.generated, this.files);

  static final _sha = RegExp(r'^[0-9a-f]{64}$');

  static _Manifest parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['format'] != DataStore._format) {
      throw FormatException('Unsupported data format ${j['format']}');
    }
    final files = [
      for (final f in (j['files'] as List).cast<Map<String, dynamic>>())
        _ManifestFile(
          f['path'] as String,
          f['sha256'] as String,
          f['bytes'] as int,
        ),
    ];
    if (files.isEmpty || files.any((f) => !_sha.hasMatch(f.sha256))) {
      throw const FormatException('Bad manifest');
    }
    return _Manifest(
      j['version'] as String,
      j['generated'] as String? ?? '',
      files,
    );
  }
}
