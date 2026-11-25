import osmium, json, math, gzip, sys, re, collections
SRC='vietnam.osm.pbf'
MODES={'bus':'bus','trolleybus':'bus','subway':'metro','light_rail':'metro','monorail':'metro','ferry':'ferry'}
def hav(a,b):
    la1,lo1,la2,lo2=map(math.radians,(a[0],a[1],b[0],b[1]))
    h=math.sin((la2-la1)/2)**2+math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 12742000*math.asin(math.sqrt(h))
rels=[]; need_w=set(); need_n=set()
class R(osmium.SimpleHandler):
    def relation(self,r):
        t={x.k:x.v for x in r.tags}
        if t.get('type')!='route' or t.get('route') not in MODES: return
        if 'construction:route' in t or t.get('railway') in('proposed','construction') or t.get('state')=='proposed' or 'proposed' in t: return
        mem=[(m.type,m.ref,m.role.strip()) for m in r.members]
        rels.append((r.id,t,mem))
        for ty,ref,ro in mem:
            (need_w if ty=='w' else need_n if ty=='n' else set()).add(ref)
R().apply_file(SRC)
print('relations',len(rels),file=sys.stderr)
ways={}; nodes={}
class W(osmium.SimpleHandler):
    def way(self,w):
        if w.id in need_w:
            try: ways[w.id]=([(n.lat,n.lon) for n in w.nodes],{x.k:x.v for x in w.tags})
            except osmium.InvalidLocationError: pass
    def node(self,n):
        if n.id in need_n: nodes[n.id]=(n.location.lat,n.location.lon,{x.k:x.v for x in n.tags})
W().apply_file(SRC,locations=True,idx='flex_mem')
print('ways',len(ways),'nodes',len(nodes),file=sys.stderr)

def stitch(wlist):
    """order-aware stitching of ways into one polyline; returns (pts, maxgap)"""
    pts=[]; gap=0
    for i,w in enumerate(wlist):
        if not w: continue
        if not pts:
            # orient first way using the next one
            nxt=next((x for x in wlist[i+1:] if x),None)
            if nxt:
                d_end=min(hav(w[-1],nxt[0]),hav(w[-1],nxt[-1])); d_start=min(hav(w[0],nxt[0]),hav(w[0],nxt[-1]))
                if d_start<d_end: w=w[::-1]
            pts=list(w); continue
        if w[0]==w[-1] and len(w)>3:  # roundabout: enter at nearest node, exit decided by next way
            k=min(range(len(w)-1),key=lambda j:hav(w[j],pts[-1])); ring=w[k:-1]+w[:k]
            nxt=next((x for x in wlist[i+1:] if x),None)
            if nxt:
                j=min(range(len(ring)),key=lambda j:min(hav(ring[j],nxt[0]),hav(ring[j],nxt[-1])))
                ring=ring[:j+1]
            gap=max(gap,hav(pts[-1],ring[0])); pts+=ring; continue
        a=hav(pts[-1],w[0]); b=hav(pts[-1],w[-1])
        if b<a: w=w[::-1]; a=b
        gap=max(gap,a); pts+=w if a>0.5 else w[1:]
    return pts,gap

def project(pts,cum,p,start):
    """nearest position on polyline at/after index start; returns (dist, seg index, t)"""
    best=(1e18,start,0.0); coslat=math.cos(math.radians(p[0]))
    for i in range(start,len(pts)-1):
        ax=(pts[i][1]-p[1])*coslat; ay=pts[i][0]-p[0]; bx=(pts[i+1][1]-p[1])*coslat; by=pts[i+1][0]-p[0]
        dx=bx-ax; dy=by-ay; L=dx*dx+dy*dy
        t=0 if L==0 else max(0,min(1,-(ax*dx+ay*dy)/L))
        d=math.hypot(ax+t*dx,ay+t*dy)*111320
        if d<best[0]-1e-9: best=(d,i,t)
        # stop at the first good local match so a later pass of the line near the stop cannot steal it
        if best[0]<40 and d>best[0]+150: break
    return best

def simplify(pts,eps):
    if len(pts)<3: return pts
    keep=[False]*len(pts); keep[0]=keep[-1]=True; st=[(0,len(pts)-1)]
    while st:
        a,b=st.pop(); 
        if b<=a+1: continue
        coslat=math.cos(math.radians(pts[a][0])); ax,ay=pts[a][1]*coslat,pts[a][0]; bx,by=pts[b][1]*coslat,pts[b][0]
        dx,dy=bx-ax,by-ay; L=dx*dx+dy*dy; md=-1; mi=a
        for i in range(a+1,b):
            px,py=pts[i][1]*coslat-ax,pts[i][0]-ay
            t=0 if L==0 else max(0,min(1,(px*dx+py*dy)/L))
            d=math.hypot(px-t*dx,py-t*dy)*111320
            if d>md: md,mi=d,i
        if md>eps: keep[mi]=True; st+=[(a,mi),(mi,b)]
    return [p for p,k in zip(pts,keep) if k]

def enc(pts):
    out=[]; pl=po=0
    for la,lo in pts:
        a=round(la*1e5); o=round(lo*1e5)
        for v in (a-pl,o-po):
            v=~(v<<1) if v<0 else v<<1
            while v>=0x20: out.append(chr((0x20|(v&0x1f))+63)); v>>=5
            out.append(chr(v+63))
        pl,po=a,o
    return ''.join(out)

def headway(t):
    v=t.get('interval') or t.get('headway')
    if not v: return None
    m=re.match(r'^(\d+):(\d+)(?::\d+)?$',v)
    if m: return int(m[1])*60+int(m[2]) or None
    m=re.match(r'^(\d+)',v)
    if m: return int(m[1]) or None

import heapq
def graph_shape(wl,spts):
    adj=collections.defaultdict(list)
    for w in wl:
        for a,b in zip(w,w[1:]):
            d=hav(a,b); adj[a].append((b,d)); adj[b].append((a,d))
    keys=list(adj)
    grid=collections.defaultdict(list)
    for k in keys: grid[(int(k[0]*200),int(k[1]*200))].append(k)
    def near(p):
        best=None; bd=300
        gx,gy=int(p[0]*200),int(p[1]*200)
        for dx in(-1,0,1):
            for dy in(-1,0,1):
                for k in grid.get((gx+dx,gy+dy),()):
                    d=hav(p,k)
                    if d<bd: bd=d; best=k
        return best
    def path(a,b,limit):
        dist={a:0}; prev={}; pq=[(0,a)]
        while pq:
            d,u=heapq.heappop(pq)
            if u==b:
                out=[b]
                while out[-1]!=a: out.append(prev[out[-1]])
                return out[::-1]
            if d>dist.get(u,1e18) or d>limit: continue
            for v,w in adj[u]:
                nd=d+w
                if nd<dist.get(v,1e18): dist[v]=nd; prev[v]=u; heapq.heappush(pq,(nd,v))
        return None
    ns=[near(p) for p in spts]
    shape=[spts[0]]; idx=[0]; found=0
    for k in range(1,len(spts)):
        a,b=ns[k-1],ns[k]; seg=None
        if a and b and a!=b:
            seg=path(a,b,3*hav(spts[k-1],spts[k])+400)
        if seg: found+=1; shape+=simplify(seg,8)
        shape.append(spts[k]); idx.append(len(shape)-1)
    return shape,idx,found
CITIES=[('Hà Nội',21.028,105.834),('TP. Hồ Chí Minh',10.776,106.701),('Đà Nẵng',16.054,108.202),('Hải Phòng',20.845,106.688),('Cần Thơ',10.045,105.747),
('Biên Hòa - Đồng Nai',10.945,106.824),('Bình Dương',11.02,106.65),('Bắc Ninh',21.186,106.076),('Long Xuyên - An Giang',10.386,105.435),('Bến Tre',10.243,106.376),
('Vĩnh Phúc',21.309,105.604),('Phú Quốc',10.227,103.96),('Huế',16.463,107.59),('Nha Trang',12.239,109.197),('Vũng Tàu',10.346,107.084),('Đà Lạt',11.94,108.458),
('Buôn Ma Thuột',12.667,108.038),('Hạ Long - Quảng Ninh',20.951,107.08),('Móng Cái',21.525,107.966),('Hòa Bình',20.817,105.338),('Quy Nhơn',13.782,109.219),('Vinh',18.679,105.681),('Thanh Hóa',19.807,105.776),('Nam Định',20.42,106.168),('Thái Nguyên',21.594,105.848),('Tây Ninh',11.31,106.098),('Mỹ Tho',10.36,106.36),('Rạch Giá',10.012,105.081),('Châu Đốc',10.705,105.117)]
NET_CITY=[('Hồ Chí Minh','TP. Hồ Chí Minh'),('Ho Chi Minh','TP. Hồ Chí Minh'),('Hanoi','Hà Nội'),('DanaBus','Đà Nẵng'),('Hải Phòng','Hải Phòng'),('Cần Thơ','Cần Thơ'),('Đồng Nai','Biên Hòa - Đồng Nai'),('Bình Dương','Bình Dương'),('Bacninh','Bắc Ninh'),('An Giang','Long Xuyên - An Giang'),('Bến Tre','Bến Tre'),('Vĩnh Phúc','Vĩnh Phúc'),('Phú Quốc','Phú Quốc')]
stop_idx={}; stops=[]; routes=[]; stats=collections.Counter()
def stop_of(key,lat,lon,name):
    if key not in stop_idx:
        stop_idx[key]=len(stops); stops.append([round(lat,6),round(lon,6),name or ''])
    return stop_idx[key]
for rid,t,mem in rels:
    mode=MODES[t['route']]
    plat=[m for m in mem if m[2].startswith('platform') and m[0] in 'nw']
    stp=[m for m in mem if (m[2].startswith('stop') or m[2] in('bus_stop','from','to','station')) and m[0]=='n']
    bare=[m for m in mem if m[2]=='' and m[0]=='n']
    cand=stp if (mode=='metro' and len(stp)>=2) else plat if len(plat)>=2 else stp if len(stp)>=2 else bare
    seq=[]
    for ty,ref,ro in cand:
        if ty=='n':
            if ref not in nodes: continue
            la,lo,tg=nodes[ref]; nm=tg.get('name:vi') or tg.get('name')
        else:
            if ref not in ways: continue
            p,tg=ways[ref]; la=sum(x[0] for x in p)/len(p); lo=sum(x[1] for x in p)/len(p); nm=tg.get('name:vi') or tg.get('name')
        i=stop_of((ty,ref),la,lo,nm)
        if not seq or seq[-1]!=i: seq.append(i)
    if len(seq)<2: stats['skip_few_stops']+=1; continue
    spts=[(stops[i][0],stops[i][1]) for i in seq]
    wl=[ways[ref][0] for ty,ref,ro in mem if ty=='w' and not ro.startswith('platform') and ref in ways]
    line,gap=stitch(wl) if wl else ([],0)
    shape=None
    if len(line)>=2 and gap<400:
        pos=[]; start=0; ok=True; far=0
        for p in spts:
            d,i,tt=project(line,None,p,start)
            if d>250: far+=1
            pos.append((i,tt)); start=i
        if far<=max(1,len(spts)//5):
            shape=[]; idx=[]
            for k,(i,tt) in enumerate(pos):
                a,b=line[i],line[i+1]; q=(a[0]+tt*(b[0]-a[0]),a[1]+tt*(b[1]-a[1]))
                if k>0:
                    pi,pt=pos[k-1]
                    seg=simplify([shape[-1]]+line[pi+1:i+1]+[q],8) if (i,tt)>(pi,pt) else [shape[-1],q]
                    shape+=seg[1:]
                else: shape.append(q)
                idx.append(len(shape)-1)
            cc=[0]
            for a,b in zip(shape,shape[1:]): cc.append(cc[-1]+hav(a,b))
            bad=sum(1 for k in range(1,len(spts)) if cc[idx[k]]-cc[idx[k-1]] < 0.7*hav(spts[k-1],spts[k])-30)
            if bad: stats['shape_rejected']+=1; shape=None
    if shape is None and wl:
        shape,idx,nfound=graph_shape(wl,spts)
        stats['graph_'+mode]+=1; stats['graph_pairs_found']+=nfound; stats['graph_pairs_total']+=len(spts)-1
    elif shape is None:
        stats['straight_'+mode]+=1; shape=spts; idx=list(range(len(spts)))
    else: stats['shaped_'+mode]+=1
    cum=[0]
    for a,b in zip(shape,shape[1:]): cum.append(cum[-1]+hav(a,b))
    dist=[round(cum[i]) for i in idx]
    if shape is not spts and dist[-1]>3*sum(hav(a,b) for a,b in zip(spts,spts[1:]))+2000:
        stats['bad_shape']+=1; shape=spts; idx=list(range(len(spts))); cum=[0]
        for a,b in zip(shape,shape[1:]): cum.append(cum[-1]+hav(a,b))
        dist=[round(c) for c in cum]
    c0=spts[len(spts)//2]; city='Khác'; bd=70000
    for nm,la,lo in CITIES:
        d=hav(c0,(la,lo))
        if d<bd: bd=d; city=nm
    net=t.get('network','')
    for key,nm in NET_CITY:
        if key in net: city=nm
    routes.append({'city':city,'id':rid,'ref':t.get('ref',''),'name':t.get('name:vi') or t.get('name',''),'from':t.get('from',''),'to':t.get('to',''),
        'mode':mode,'net':t.get('network',''),'op':t.get('operator',''),'col':t.get('colour',''),'hw':headway(t),'oh':t.get('opening_hours',''),
        'charge':t.get('charge',''),'stops':seq,'dist':dist,'idx':idx,'shape':enc(shape)})
# unnamed stops: leave blank; drop unused
print(dict(stats),'routes',len(routes),'stops',len(stops),'named',sum(1 for s in stops if s[2]),file=sys.stderr)
data={'generated':sys.argv[1] if len(sys.argv)>1 else '','source':'OpenStreetMap contributors (ODbL), Geofabrik Vietnam extract','stops':stops,'routes':routes}
raw=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode()
open('transit.json','wb').write(raw); open('transit.json.gz','wb').write(gzip.compress(raw,9))
print(len(raw),len(gzip.compress(raw,9)),file=sys.stderr)
