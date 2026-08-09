# 지적경계 폴리곤 통합 지도

인접필지를 하나의 획지로 보여줄 때, 개별 필지 경계 + 전체 테두리 + 중심점을 오버레이.

## 경계 수집 (WFS)
```python
# 개별 PNU 조회 (attrFilter) 또는 bbox 일괄 (geomFilter)
params={"key":KEY,"domain":"localhost","service":"data","request":"GetFeature",
        "data":"LP_PA_CBND_BUBUN","attrFilter":f"pnu:=:{pnu}",  # 또는 geomFilter:BOX(...)
        "format":"json","geometry":"true","size":"5","crs":"EPSG:4326"}
# geometry.type: MultiPolygon → coordinates[poly][0]=외곽ring(lon,lat)
```

## 좌표→픽셀 (Web Mercator)
```python
def mx(lon): return lon*20037508.34/180.0
def my(lat):
    y=math.log(math.tan((90+lat)*math.pi/360.0))/(math.pi/180.0)
    return y*20037508.34/180.0
res=156543.03392*math.cos(math.radians(cy))/(2**zoom)  # m/px
def to_px(lon,lat):
    return (W/2+(mx(lon)-cmx)/res, H/2-(my(lat)-cmy)/res)
```

## 배경지도 (VWorld Static)
```python
url="https://api.vworld.kr/req/image?"+urllib.parse.urlencode({
    "service":"image","request":"getmap","key":KEY,"format":"png",
    "basemap":"GRAPHIC","center":f"{cx},{cy}","crs":"EPSG:4326",
    "zoom":str(zoom),"size":f"{W},{H}","domain":"localhost"})
# ⚠️ zoom19는 실패 → zoom18 고정 사용
```

## 오버레이 요소
1. 개별 필지: 파란 반투명 채움(0,161,224,55) + 파란 테두리.
2. 전체 외곽: convex hull → 흰 굵은선(7px) + 빨간선(4px) 이중.
3. 중심점: 흰 테두리 + 빨간 원(r15) + 흰 중심점.
4. 필지 라벨: 지번 + 면적(㎡) 중앙 배치.
5. 헤더 바(감청 배경) + 범례.

## 폰트
`/System/Library/Fonts/AppleSDGothicNeo.ttc` (macOS 한글).

전체 구현은 이 스킬 작업 히스토리의 `make_polygon_map.py`/`goesan_poly.py` 참조.
