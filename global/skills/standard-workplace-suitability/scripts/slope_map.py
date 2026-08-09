import json, math, urllib.request, urllib.parse, io
from PIL import Image, ImageDraw, ImageFont
KEY="62111428-86F4-3538-9BEB-13E7EB93913E"
g=json.load(open("상권분석/파주법원리/data/san40_geom.json"))
dem=json.load(open("상권분석/파주법원리/data/san40_dem.json"))
ring=g["rings"][0]
lons=[p[0] for p in ring]; lats=[p[1] for p in ring]
cx=(min(lons)+max(lons))/2; cy=(min(lats)+max(lats))/2
W,H=800,760
def mx(lon): return lon*20037508.34/180.0
def my(lat):
    y=math.log(math.tan((90+lat)*math.pi/360.0))/(math.pi/180.0); return y*20037508.34/180.0
zoom=17
url=("https://api.vworld.kr/req/image?"+urllib.parse.urlencode({
    "service":"image","request":"getmap","key":KEY,"format":"png","basemap":"GRAPHIC",
    "center":f"{cx},{cy}","crs":"EPSG:4326","zoom":str(zoom),"size":f"{W},{H}","domain":"localhost"}))
req=urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0"})
bg=Image.open(io.BytesIO(urllib.request.urlopen(req,timeout=40).read())).convert("RGBA")
res=156543.03392*math.cos(math.radians(cy))/(2**zoom)
cmx,cmy=mx(cx),my(cy)
def to_px(lon,lat): return (W/2+(mx(lon)-cmx)/res, H/2-(my(lat)-cmy)/res)
ov=Image.new("RGBA",bg.size,(0,0,0,0)); d=ImageDraw.Draw(ov)
# 임야 폴리곤 (굵은 초록 테두리 + 옅은 채움)
poly_px=[to_px(lo,la) for lo,la in ring]
d.polygon(poly_px, fill=(60,140,60,45), outline=(20,110,20,255))
for w,col in [(7,(255,255,255,220)),(4,(20,130,20,255))]:
    d.line(poly_px+[poly_px[0]], fill=col, width=w, joint="curve")
# 표고 점 히트맵 (표고 62~142 → 초록→노랑→빨강)
pts=dem["pts"]
emin=min(p[2] for p in pts); emax=max(p[2] for p in pts)
def color(e):
    t=(e-emin)/(emax-emin) if emax>emin else 0
    if t<0.5:  # 초록→노랑
        r=int(80+ (255-80)*(t/0.5)); gg=180; b=60
    else:
        r=230; gg=int(200-(200-60)*((t-0.5)/0.5)); b=50
    return (r,gg,b,220)
r=9
for lo,la,e in pts:
    px,py=to_px(lo,la)
    d.ellipse([px-r,py-r,px+r,py+r], fill=color(e), outline=(255,255,255,200))
out=Image.alpha_composite(bg,ov).convert("RGB")
dd=ImageDraw.Draw(out)
try:
    font=ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc",20)
    fsm=ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc",14)
except: font=fsm=ImageFont.load_default()
txt="임야 산40 경사·표고 분석 · 평균 13.2° · 표고 62~142m(고저差 80m)"
tb=dd.textbbox((0,0),txt,font=font); tw=tb[2]-tb[0]; th=tb[3]-tb[1]
dd.rectangle([10,10,10+tw+20,10+th+16], fill=(20,60,30,235))
dd.text((20,16),txt,fill=(255,255,255),font=font)
# 범례
lx,ly=W-180,H-90
dd.rectangle([lx-10,ly-10,W-10,H-10], fill=(255,255,255,235))
dd.text((lx,ly),"표고(낮음→높음)",fill=(30,30,30),font=fsm)
for i,(lab,c) in enumerate([("62m 저지",(80,180,60)),("100m 중간",(255,200,60)),("142m 고지",(230,60,50))]):
    dd.ellipse([lx,ly+22+i*20,lx+12,ly+34+i*20],fill=c)
    dd.text((lx+18,ly+20+i*20),lab,fill=(40,40,40),font=fsm)
out.save("상권분석/파주법원리/samples/파주법원리_5임야경사.png")
print("saved slope map")
