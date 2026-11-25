"""Parse route info pages saved from xe-buyt.com (TP.HCM routes) into xb.json."""
import re,html,glob,json,unicodedata
out={}
for f in sorted(glob.glob('pages/*.html')):
    s=unicodedata.normalize('NFC',open(f,encoding='utf-8',errors='replace').read())
    title=re.search(r'<title>(.*?)</title>',s,re.S)[1].strip()
    m=re.match(r'Xe buýt\s+([0-9A-Za-z\-]+)\s+(.*)',title)
    if not m: continue
    t=re.sub(r'<script.*?</script>|<style.*?</style>','',s,flags=re.S); t=html.unescape(re.sub(r'<[^>]+>',' | ',t)); t=re.sub(r'(\s*\|\s*)+',' | ',re.sub(r'\s+',' ',t))
    def g(p):
        x=re.search(p,t); return x.groups() if x else None
    r={'name':m[2].strip(),'url':'https://xe-buyt.com/'+f.split('/')[-1]}
    x=g(r'Thời gian hoạt động:\s*(\d\d:\d\d)\s*-\s*(\d\d:\d\d)')
    if x: r['first'],r['last']=x
    x=g(r'Số chuyến:\s*(\d+)')
    if x: r['trips']=int(x[0])
    x=g(r'Thời gian chuyến:\s*(\d+)(?:\s*-\s*(\d+))?\s*phút')
    if x: r['tripMin']=[int(x[0]),int(x[1] or x[0])]
    x=g(r'Giãn cách chuyến:\s*(\d+)(?:\s*-\s*(\d+))?\s*phút')
    if x: r['hw']=[int(x[0]),int(x[1] or x[0])]
    if len(r)>2: out[m[1].lstrip('0') or '0']=r
json.dump(out,open('xb.json','w'),ensure_ascii=False,indent=1)
print(len(out)); print(json.dumps(list(out.items())[:3],ensure_ascii=False))
