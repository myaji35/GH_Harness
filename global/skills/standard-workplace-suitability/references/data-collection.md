# VWorld 부지 데이터 수집 (검증된 함정 포함)

## VWorld 키
`npl-property-analysis/scripts/collect.py`에 하드코딩된 무료 키 재사용.

## ⚠️ 함정 1: NED API는 domain 파라미터 필수
VWorld NED(토지대장·공시지가·용도지역) API는 `domain=localhost`(또는 등록도메인) 없으면
`{"error":"INCORRECT_KEY"}` 반환. curl 직접 호출 시 특히 주의.
```python
q=urllib.parse.urlencode({"key":KEY,"pnu":pnu,"format":"json",
    "numOfRows":"1","pageNo":"1","domain":"localhost"})
```

## ⚠️ 함정 2: 지오코더가 부번을 본번으로 접음
`경기도 …319-8` 지오코딩 시 PNU가 `…3190000`(본번 319)으로 나와 부번 무시됨.
→ **PNU를 직접 구성**해 NED 조회:
```
PNU(19) = 법정동코드(10) + 필지구분(1) + 본번(4) + 부번(4)
  필지구분: 1=일반, 2=산
  예: 조남동 319-8 = 4139012400 + 1 + 0319 + 0008
      법원리 산40  = 4148025622 + 2 + 0040 + 0000
```

## 법정동코드 얻는 법
좌표 기반 WFS로 대상지 필지 조회 → properties.pnu 앞 10자리.
```python
box=f"BOX({minx},{miny},{maxx},{maxy})"  # EPSG:4326
params={"key":KEY,"domain":"localhost","service":"data","request":"GetFeature",
        "data":"LP_PA_CBND_BUBUN","geomFilter":box,"format":"json",
        "geometry":"true","size":"100","crs":"EPSG:4326"}
# → features[].properties.pnu / .jibun
```

## 수집 항목 (PNU 확정 후)
```python
# 토지대장 (지목·면적·소유)
get(f"https://api.vworld.kr/ned/data/ladfrlList?{q}")
  # ["ladfrlVOList"]["ladfrlVOList"] → lndcgrCodeNm(지목) lndpclAr(면적) posesnSeCodeNm(소유)
# 공시지가 시계열
get(f"https://api.vworld.kr/ned/data/getIndvdLandPriceAttr?{q}")
  # ["indvdLandPrices"]["field"] → stdrYear, pblntfPclnd(원/㎡)
# 용도지역·규제
get(f"https://api.vworld.kr/ned/data/getLandUseAttr?{q}")
  # ["landUses"]["field"] → prposAreaDstrcCodeNm, cnflcAt(1=포함 2=접함 3=저촉)
```

## 지목별 개발부담 플래그
- **답(畓)·전(田)** → 농지전용부담금(개별공시지가 30%, 상한 5만원/㎡).
- **임(林)** → 산지전용부담금·대체산림자원조성비(준보전 약 8,300원/㎡).
- 지목이 "답"인데 계획서에 "나대지"로 쓰였으면 전용 리스크 명시.

## 소유구분 검증
- "개인(0)" 표기 = 공유/특수지분 가능성 → 명도·협상 리스크.
- 소유 공란 = 국공유·도로 가능성 → 매입대상 제외 검토.
- 계획서의 "대표 개인소유" 주장과 실측 소유(법인 등) 불일치 시 반드시 보고.
