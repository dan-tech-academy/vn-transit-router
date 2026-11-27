"""Splits data/transit.json.gz into one file per city plus a manifest, and
optionally uploads them to the Cloudflare R2 bucket the app downloads from.

  python3 tool/publish_data.py            # writes dist/data/
  python3 tool/publish_data.py --upload   # also uploads with wrangler

Uploading needs CLOUDFLARE_API_TOKEN (R2 write) and CLOUDFLARE_ACCOUNT_ID.
City files live under a versioned path and never change, so they are cached
for a year; manifest.json is uploaded last and is the only file revalidated.
"""
import gzip, hashlib, json, os, re, subprocess, sys, unicodedata

SRC = 'data/transit.json.gz'
OUT = 'dist/data'
BUCKET = 'ghee-transit-data'


def slug(name):
    s = unicodedata.normalize('NFD', name.replace('Đ', 'D').replace('đ', 'd'))
    s = ''.join(c for c in s if not unicodedata.combining(c)).lower()
    return re.sub(r'[^a-z0-9]+', '-', s).strip('-')


def build():
    raw = open(SRC, 'rb').read()
    d = json.loads(gzip.decompress(raw))
    version = d['generated'].replace('-', '') + '-' + hashlib.sha256(raw).hexdigest()[:8]
    cities = {}
    for r in d['routes']:
        cities.setdefault(r['city'], []).append(r)
    os.makedirs(f'{OUT}/v/{version}', exist_ok=True)
    files = []
    for city, routes in cities.items():
        local, stops, out = {}, [], []
        for r in routes:
            r = dict(r)
            r['stops'] = [local.setdefault(s, len(local)) for s in r['stops']]
            out.append(r)
        stops = [d['stops'][s] for s in local]
        body = json.dumps(
            {'city': city, 'stops': stops, 'routes': out},
            ensure_ascii=False, separators=(',', ':'),
        ).encode()
        blob = gzip.compress(body, 9, mtime=0)
        path = f'v/{version}/{slug(city)}.json.gz'
        open(f'{OUT}/{path}', 'wb').write(blob)
        files.append({
            'city': city, 'path': path, 'bytes': len(blob),
            'sha256': hashlib.sha256(blob).hexdigest(),
            'routes': len(out), 'stops': len(stops),
        })
    manifest = {
        'format': 1, 'version': version, 'generated': d['generated'],
        'source': d['source'], 'files': files,
    }
    with open(f'{OUT}/manifest.json', 'w') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print(version, len(files), 'files', sum(x['bytes'] for x in files), 'bytes')
    return manifest


def put(key, content_type, cache):
    subprocess.run([
        'npx', '--yes', 'wrangler@4', 'r2', 'object', 'put', f'{BUCKET}/{key}',
        '--file', f'{OUT}/{key}', '--remote',
        '--content-type', content_type, '--cache-control', cache,
    ], check=True)


if __name__ == '__main__':
    m = build()
    if '--upload' in sys.argv:
        for f in m['files']:
            put(f['path'], 'application/gzip', 'public, max-age=31536000, immutable')
        put('manifest.json', 'application/json', 'public, max-age=300')
