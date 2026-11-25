"""Per-route corrections applied after extract_osm.py and merge_schedule.py.

tool/route_fixes.json lists:
- "reorder": relations whose stop order in OpenStreetMap is scrambled. Their
  stops are put in travel order between the named first and last stop
  (shortest path through all of them). The road geometry of such a relation
  cannot be trusted, so the shape becomes straight lines between stops.
- "hours": operating hours for lines that have none mapped, with the source.
Safe to run again: a relation already in order is left as it is.
"""
import gzip, json, math

def hav(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 12742000 * math.asin(math.sqrt(h))

def enc(pts):
    out = []; pl = po = 0
    for la, lo in pts:
        a = round(la * 1e5); o = round(lo * 1e5)
        for v in (a - pl, o - po):
            v = ~(v << 1) if v < 0 else v << 1
            while v >= 0x20: out.append(chr((0x20 | (v & 0x1f)) + 63)); v >>= 5
            out.append(chr(v + 63))
        pl, po = a, o
    return ''.join(out)

def order(ids, P, first, last):
    """Open path first..last through every stop: nearest neighbour, then 2-opt."""
    rest = [i for i in ids if i not in (first, last)]
    path = [first]
    while rest:
        nxt = min(rest, key=lambda i: hav(P[path[-1]], P[i]))
        rest.remove(nxt); path.append(nxt)
    path.append(last)
    d = lambda a, b: hav(P[path[a]], P[path[b]])
    improved = True
    while improved:
        improved = False
        for i in range(1, len(path) - 2):
            for j in range(i + 1, len(path) - 1):
                if d(i - 1, j) + d(i, j + 1) < d(i - 1, i) + d(j, j + 1) - 1:
                    path[i:j + 1] = path[i:j + 1][::-1]; improved = True
        # Or-opt: move a short run of stops to a better place.
        for n in range(1, 13):
            for i in range(1, len(path) - n):
                run = path[i:i + n]; rest = path[:i] + path[i + n:]
                gain = hav(P[path[i - 1]], P[run[0]]) + hav(P[run[-1]], P[path[i + n]]) - hav(P[path[i - 1]], P[path[i + n]])
                for k in range(1, len(rest)):
                    for seg in (run, run[::-1]):
                        cost = hav(P[rest[k - 1]], P[seg[0]]) + hav(P[seg[-1]], P[rest[k]]) - hav(P[rest[k - 1]], P[rest[k]])
                        if cost < gain - 1:
                            path = rest[:k] + seg + rest[k:]; improved = True; break
                    else: continue
                    break
                if improved: break
            if improved: break
    return path

path = 'assets/data/transit.json.gz'
data = json.load(gzip.open(path))
fixes = json.load(open('tool/route_fixes.json'))
stops = data['stops']
by_id = {r['id']: r for r in data['routes']}
for fix in fixes['reorder']:
    r = by_id[fix['id']]
    ids = list(dict.fromkeys(r['stops']))
    named = lambda name: [i for i in ids if stops[i][2] == name]
    # Of several stops with the end's name, take the outermost one.
    a0, b0 = named(fix['first'])[0], named(fix['last'])[0]
    first = max(named(fix['first']), key=lambda i: hav(stops[i], stops[b0]))
    last = max(named(fix['last']), key=lambda i: hav(stops[i], stops[a0]))
    seq = order(ids, stops, first, last)
    if seq == r['stops']:
        continue
    pts = [(stops[i][0], stops[i][1]) for i in seq]
    dist = [0]
    for a, b in zip(pts, pts[1:]): dist.append(dist[-1] + hav(a, b))
    print(r['ref'], r['city'], r['dist'][-1], '->', round(dist[-1]), 'm')
    r.update(stops=seq, dist=[round(x) for x in dist], idx=list(range(len(seq))), shape=enc(pts))
for fix in fixes['hours']:
    for r in data['routes']:
        if r['ref'] == fix['ref'] and r['city'] == fix['city'] and r['mode'] == fix['mode'] and not r.get('oh'):
            r['oh'] = fix['oh']; filled = ['giờ chạy']
            if not r.get('hw') and fix.get('hw'):
                r['hw'] = fix['hw']; filled.append('giãn cách')
            r['sched'] = fix['source']; r['schedf'] = ', '.join(filled)
            print(r['ref'], r['city'], 'hours', r['oh'])
with gzip.open(path, 'wt', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
