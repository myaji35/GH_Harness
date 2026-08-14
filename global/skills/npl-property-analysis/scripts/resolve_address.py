"""건물명 → 상세주소 해석 헬퍼.
건물명(예: "강남 헤븐리치 더 시그니처")만 있고 지번을 모를 때 사용.

전략 (순서대로 시도):
  1) VWorld 지오코딩에 건물명 그대로 (대개 실패 — 참고용)
  2) [AI 에이전트가 수행] WebSearch로 "건물명 + 분양/주소/지번" 검색 →
     기사·분양페이지에서 도로명주소 또는 지번 추출
  3) 추출한 도로명/지번을 VWorld로 verify() → 좌표·토지대장 일치 확인

이 스크립트는 3)의 verify를 담당한다. 2)는 에이전트가 WebSearch로 수행 후
결과 주소를 이 스크립트에 넘긴다.

Usage:
  python3 resolve_address.py --verify-road "서울특별시 강남구 강남대로 302"
  python3 resolve_address.py --verify-parcel "서울특별시 강남구 역삼동 837-10"
"""
import sys, json, argparse, urllib.request, urllib.parse

KEY = "62111428-86F4-3538-9BEB-13E7EB93913E"
DOMAIN = "http://localhost"

def _get(url):
    req = urllib.request.Request(url, headers={"Referer": DOMAIN})
    return json.loads(urllib.request.urlopen(req, timeout=20).read().decode("utf-8"))

def geocode(address, gtype):
    q = urllib.parse.urlencode({
        "service": "address", "request": "getcoord", "version": "2.0",
        "crs": "epsg:4326", "address": address, "type": gtype,
        "format": "json", "key": KEY})
    r = _get(f"https://api.vworld.kr/req/address?{q}").get("response", {})
    if r.get("status") != "OK":
        return None
    p = r["result"]["point"]
    return {"x": float(p["x"]), "y": float(p["y"]),
            "refined": r.get("refined", {}).get("text", address)}

def verify(address, gtype):
    """도로명/지번 주소가 실재하는지 VWorld로 검증. 좌표+정제주소 반환."""
    g = geocode(address, gtype)
    if not g:
        return {"ok": False, "input": address, "type": gtype}
    return {"ok": True, "input": address, "type": gtype, **g}

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify-road")
    ap.add_argument("--verify-parcel")
    a = ap.parse_args()
    if a.verify_road:
        print(json.dumps(verify(a.verify_road, "road"), ensure_ascii=False, indent=2))
    elif a.verify_parcel:
        print(json.dumps(verify(a.verify_parcel, "parcel"), ensure_ascii=False, indent=2))
    else:
        ap.print_help()
