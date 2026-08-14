"""NPL 물건지 데이터 수집 — VWorld 무료 API.
주소 → 좌표(지오코딩) → PNU(역지오코딩) → 토지대장·공시지가·용도지역.
Usage:
  python3 collect.py "서울특별시 강남구 청담동 49-8"
  python3 collect.py "..." --json out.json
무료 범위: 지번·지목·면적·소유·공시지가(시계열)·용도지역·좌표. (실거래·경매·감정가는 유료/별도키)
"""
import sys, json, argparse, urllib.request, urllib.parse

KEY = "62111428-86F4-3538-9BEB-13E7EB93913E"  # VWorld 무료 키 (필요 시 교체)
DOMAIN = "http://localhost"

def _get(url):
    req = urllib.request.Request(url, headers={"Referer": DOMAIN})
    return json.loads(urllib.request.urlopen(req, timeout=20).read().decode("utf-8"))

def geocode(address, gtype="parcel"):
    q = urllib.parse.urlencode({
        "service": "address", "request": "getcoord", "version": "2.0",
        "crs": "epsg:4326", "address": address, "type": gtype,
        "format": "json", "key": KEY})
    r = _get(f"https://api.vworld.kr/req/address?{q}").get("response", {})
    if r.get("status") != "OK":
        return None
    p = r["result"]["point"]
    return float(p["x"]), float(p["y"]), r.get("refined", {}).get("text", address)

def reverse_pnu(x, y):
    """좌표 → 법정동코드로 PNU 조립 (지번은 refined에서)."""
    q = urllib.parse.urlencode({
        "service": "address", "request": "getAddress", "version": "2.0",
        "crs": "epsg:4326", "point": f"{x},{y}", "type": "parcel",
        "format": "json", "key": KEY})
    res = _get(f"https://api.vworld.kr/req/address?{q}").get("response", {}).get("result", [])
    if not res:
        return None
    s = res[0].get("structure", {})
    ld = s.get("level4LC")           # 법정동 10자리
    jibun = s.get("level5", "")      # "44-5" 또는 "44"
    if not ld or not jibun:
        return None
    mountain = "2" if s.get("detail", "").startswith("산") else "1"
    parts = jibun.replace("산", "").split("-")
    bon = parts[0].zfill(4)
    bu = (parts[1] if len(parts) > 1 else "0").zfill(4)
    return f"{ld}{mountain}{bon}{bu}", res[0].get("text")

def land(pnu):
    q = urllib.parse.urlencode({"key": KEY, "pnu": pnu, "format": "json",
                                "numOfRows": 1, "domain": DOMAIN})
    v = _get(f"https://api.vworld.kr/ned/data/ladfrlList?{q}").get(
        "ladfrlVOList", {}).get("ladfrlVOList", [])
    if not v:
        return None
    a = v[0]
    return {"addr": f"{a['ldCodeNm']} {a['mnnmSlno']}", "jimok": a["lndcgrCodeNm"],
            "area": float(a["lndpclAr"]), "owner": a["posesnSeCodeNm"]}

def land_price(pnu):
    q = urllib.parse.urlencode({"key": KEY, "pnu": pnu, "format": "json",
                                "numOfRows": 100, "domain": DOMAIN})
    f = _get(f"https://api.vworld.kr/ned/data/getIndvdLandPriceAttr?{q}").get(
        "indvdLandPrices", {}).get("field", [])
    series = {}
    for x in f:
        y = x.get("stdrYear")
        if y:
            series[y] = int(x.get("pblntfPclnd", 0))
    return series  # {year: 원/㎡}

def land_use(pnu):
    q = urllib.parse.urlencode({"key": KEY, "pnu": pnu, "format": "json",
                                "numOfRows": 30, "domain": DOMAIN})
    f = _get(f"https://api.vworld.kr/ned/data/getLandUseAttr?{q}").get(
        "landUses", {}).get("field", [])
    return [f"{x['prposAreaDstrcCodeNm']}({x['cnflcAtNm']})" for x in f]

def collect(address):
    g = geocode(address)
    if not g:
        return {"error": f"지오코딩 실패: {address}"}
    x, y, refined = g
    rp = reverse_pnu(x, y)
    if not rp:
        return {"error": "PNU 확보 실패", "x": x, "y": y}
    pnu, addr_text = rp
    prices = land_price(pnu)
    latest_year = max(prices) if prices else None
    return {
        "input": address, "refined": refined or addr_text, "x": x, "y": y,
        "pnu": pnu, "land": land(pnu),
        "price_latest_year": latest_year,
        "price_latest": prices.get(latest_year) if latest_year else None,
        "price_series": prices, "land_use": land_use(pnu),
    }

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("address")
    ap.add_argument("--json", help="결과 저장 경로")
    a = ap.parse_args()
    result = collect(a.address)
    out = json.dumps(result, ensure_ascii=False, indent=2)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            f.write(out)
    print(out)
