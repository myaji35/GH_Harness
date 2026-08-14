"""물건지 위치도 3단(원거리·중거리·클로즈업) 생성 — VWorld 배경지도+지적도+마커.
무료 API만 사용. 중심 좌표를 화면 정중앙에 두므로 마커도 정중앙.
Usage (모듈):
  import make_map as m
  m.make_3zoom(x, y, name="청담_49-8", label="물건지 · 논현동 49-8", outdir="samples")
Usage (CLI):
  python3 make_map.py <x> <y> <name> <label> [outdir]
"""
import sys, os, urllib.request, urllib.parse
from io import BytesIO
from PIL import Image, ImageDraw, ImageFont

KEY = "62111428-86F4-3538-9BEB-13E7EB93913E"
DOMAIN = "http://localhost"
SIZE = 640

def fetch(url):
    req = urllib.request.Request(url, headers={"Referer": DOMAIN})
    return Image.open(BytesIO(urllib.request.urlopen(req, timeout=20).read())).convert("RGBA")

def static_basemap(x, y, zoom, basemap="GRAPHIC"):
    q = urllib.parse.urlencode({
        "service": "image", "request": "getmap", "key": KEY, "format": "png",
        "basemap": basemap, "center": f"{x},{y}", "crs": "EPSG:4326",
        "zoom": zoom, "size": f"{SIZE},{SIZE}", "domain": DOMAIN})
    return fetch(f"https://api.vworld.kr/req/image?{q}")

def cadastral_wms(x, y, half_deg):
    bbox = f"{y-half_deg},{x-half_deg},{y+half_deg},{x+half_deg}"
    q = urllib.parse.urlencode({
        "SERVICE": "WMS", "REQUEST": "GetMap", "VERSION": "1.3.0",
        "LAYERS": "lp_pa_cbnd_bubun,lp_pa_cbnd_bonbun", "CRS": "EPSG:4326",
        "BBOX": bbox, "WIDTH": SIZE, "HEIGHT": SIZE, "FORMAT": "image/png",
        "TRANSPARENT": "true", "EXCEPTIONS": "text/xml", "key": KEY, "domain": DOMAIN})
    return fetch(f"https://api.vworld.kr/req/wms?{q}")

def draw_marker(img, label, r=16, show_label=True):
    d = ImageDraw.Draw(img)
    cx, cy = SIZE // 2, SIZE // 2
    d.ellipse([cx-r-2, cy-r-2, cx+r+2, cy+r+2], fill=(0,0,0,60))
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(230,30,30,255), outline=(255,255,255,255), width=3)
    d.polygon([(cx-8, cy+r-2), (cx+8, cy+r-2), (cx, cy+r+16)], fill=(230,30,30,255))
    d.ellipse([cx-5, cy-5, cx+5, cy+5], fill=(255,255,255,255))
    if not show_label:
        return img
    try:
        font = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 20)
    except Exception:
        font = ImageFont.load_default()
    tb = d.textbbox((0,0), label, font=font)
    tw, th = tb[2]-tb[0], tb[3]-tb[1]
    bx0, by0 = cx - tw//2 - 10, cy - r - th - 20
    d.rounded_rectangle([bx0, by0, bx0+tw+20, by0+th+12], radius=6, fill=(22,50,92,235))
    d.text((bx0+10, by0+4), label, font=font, fill=(255,255,255,255))
    return img

def make(x, y, zoom, half_deg, label, out, cadastral=True, marker_r=16, show_label=True):
    base = static_basemap(x, y, zoom)
    if cadastral:
        base.alpha_composite(cadastral_wms(x, y, half_deg))
    base = draw_marker(base, label, r=marker_r, show_label=show_label)
    base.convert("RGB").save(out, "PNG")
    print("saved:", out)

def make_3zoom(x, y, name, label, outdir="samples"):
    os.makedirs(outdir, exist_ok=True)
    make(x, y, zoom=14, half_deg=0.006,  label=label, cadastral=False,
         marker_r=14, out=f"{outdir}/{name}_1원거리.png")
    make(x, y, zoom=17, half_deg=0.0016, label=label, cadastral=True,
         marker_r=16, out=f"{outdir}/{name}_2중거리.png")
    make(x, y, zoom=18, half_deg=0.0007, label=label, cadastral=True,
         marker_r=13, show_label=False, out=f"{outdir}/{name}_3클로즈업.png")

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python3 make_map.py <x> <y> <name> <label> [outdir]")
        sys.exit(1)
    x, y, name, label = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4]
    outdir = sys.argv[5] if len(sys.argv) > 5 else "samples"
    make_3zoom(x, y, name, label, outdir)
