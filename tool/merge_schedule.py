"""Merge operating hours and headway from tool/hcm_schedule.json
(parsed from xe-buyt.com route pages) into data/transit.json.gz.

Only TP. Hồ Chí Minh bus routes are matched, by route number. and only when both
endpoints named on the page are the termini of the OpenStreetMap route. A value
already mapped in OpenStreetMap is kept; the schedule only fills what is missing.
Fares on those pages are incomplete and outdated, so they are not used.
"""
import gzip, json, re, sys, unicodedata

GENERIC = set('ben xe buyt bx cho khu dan cu dai hoc truong cong vien kcn kcx thpt'.split())

def words(s):
    s = unicodedata.normalize('NFD', s.lower().replace('đ', 'd'))
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return set(re.findall(r'[a-z0-9]+', s)) - GENERIC

def same_place(a, b):
    wa = words(a)
    return bool(wa) and len(wa & words(b)) / len(wa) > 0.5

def same_line(sched_name, r):
    """Both page endpoints are the route's two termini, in either order."""
    parts = [p for p in re.split(r'\s*[-–]\s*', sched_name) if p.strip()]
    if len(parts) < 2:
        return False
    a, b = parts[0], parts[-1]
    return (same_place(a, r['from']) and same_place(b, r['to'])) or \
           (same_place(a, r['to']) and same_place(b, r['from']))

sched = json.load(open(sys.argv[1] if len(sys.argv) > 1 else 'tool/hcm_schedule.json'))
path = 'data/transit.json.gz'
d = json.load(gzip.open(path))
n = 0
for r in d['routes']:
    s = sched.get(r['ref'].lstrip('0') or '0')
    if not s or r['city'] != 'TP. Hồ Chí Minh' or r['mode'] != 'bus' or not same_line(s['name'], r):
        continue
    filled = []
    if not r.get('oh') and s.get('first'):
        r['oh'] = f"Mo-Su {s['first']}-{s['last']}"; filled.append('giờ chạy')
    if not r.get('hw') and s.get('hw'):
        r['hw'] = round(sum(s['hw']) / 2); filled.append('giãn cách')
    if filled:
        r['sched'] = 'xe-buyt.com'; r['schedf'] = ', '.join(filled); n += 1
d['source'] = d['source'].split('; ')[0] + '; xe-buyt.com (giờ chạy, giãn cách tuyến TP.HCM)'
with gzip.open(path, 'wt', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, separators=(',', ':'))
print('routes updated:', n)
