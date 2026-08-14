import json, urllib.request, urllib.parse, math, time
def get(url,timeout=30):
    req=urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))
g=json.load(open("상권분석/파주법원리/data/san40_geom.json"))
ring=g["rings"][0]  # [[lon,lat],...]
minx=min(p[0] for p in ring); maxx=max(p[0] for p in ring)
miny=min(p[1] for p in ring); maxy=max(p[1] for p in ring)
def inside(lon,lat,poly):
    n=len(poly); ins=False; j=n-1
    for i in range(n):
        xi,yi=poly[i]; xj,yj=poly[j]
        if ((yi>lat)!=(yj>lat)) and (lon < (xj-xi)*(lat-yi)/(yj-yi+1e-15)+xi): ins=not ins
        j=i
    return ins
# 격자 ~25m 간격 (위도 1도≈111km, 25m≈0.000225도)
step_lat=0.000225; step_lon=0.000225/math.cos(math.radians((miny+maxy)/2))
pts=[]
lat=miny
while lat<=maxy:
    lon=minx
    while lon<=maxx:
        if inside(lon,lat,ring): pts.append((lon,lat))
        lon+=step_lon
    lat+=step_lat
print("격자점(폴리곤내부):",len(pts))
# opentopodata 배치 (최대 100/req)
elevs={}
for i in range(0,len(pts),90):
    batch=pts[i:i+90]
    locs="|".join(f"{la},{lo}" for lo,la in batch)
    try:
        r=get(f"https://api.opentopodata.org/v1/srtm30m?locations={urllib.parse.quote(locs)}")
        for (lo,la),res in zip(batch,r["results"]):
            elevs[(lo,la)]=res["elevation"]
    except Exception as e:
        print("batch err",e)
    time.sleep(1.1)  # rate limit
print("표고 수집:",len(elevs))
json.dump({"pts":[[lo,la,elevs.get((lo,la))] for lo,la in pts if elevs.get((lo,la)) is not None],
           "step_lat":step_lat,"step_lon":step_lon},
          open("상권분석/파주법원리/data/san40_dem.json","w"))
# 표고 통계
vals=[v for v in elevs.values() if v is not None]
print(f"표고 min={min(vals):.0f} max={max(vals):.0f} range={max(vals)-min(vals):.0f}m 평균={sum(vals)/len(vals):.0f}m")
