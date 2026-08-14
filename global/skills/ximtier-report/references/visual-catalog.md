# 시각물 카탈로그 — 실재 / 신규개발 필요

> cards.json 42장 전수 기준. Opus 직접 실측 대조 완료.


### 실재 — 지금 바로 쓸 수 있는 것

| 시각물 | 무엇을 보여주나 | 출처 | 쓰는 p | 현업 판단 포인트 |
|---|---|---|---|---|
| ERD 다이어그램 | 고객 DB 테이블·관계(FK) 지도 | erd_view(실선·map)·/api/erd | 13 | "우리 데이터를 손대지 않고 읽는구나" |
| 지식그래프(별빛 네트워크) | 변수 상관 관계망+임계값 슬라이더 | kg_view(실선·map)·/api/kg | 18 | 성과와 굵게 연결된 관리 후보 |
| 이진 의사결정트리 SVG+AI 해설 | 성과 갈림길과 한국어 해설 | algo_train(실선·tree)·/api/tree-svg | 24 | 어느 조건에서 좋은 날이 되나 |
| 다진 트리(ID3) SVG | 구간 언어의 갈림길 | /api/id3-tree·id3_tree.py | 25 | 구간별 운영 기준 |
| 변수 중요도 막대 | 성과 기여도 순위 | target_y_setup(실선·chart) | 23 | 1순위 지렛대 |
| 5분위 구간 막대 | 상·하위 구간 특성 | y_quintile_filter(실선·chart) | 19 | 상위 20% 날의 공통점 |
| What-if 델타/민감도 | 조건 변화 시 성과 이동 | whatif(실선·chart)·plotly | 32 | 지렛대의 체감 효과 |
| RWI 전략 비교표 | 5전략 도달치·변수별 현재→목표 | rwi_result(실선)·/api/pro/reverse-whatif | 30·31 | 어느 길을 택할까 |
| 트리거 네트워크 SVG | 사건→파급 연쇄 | trigger_sim(실선·map)·/api/trigger | 산업 선택 | 조기경보 걸 변수 |
| 워드클라우드·키워드 막대 | 텍스트/SNS 키워드 | sns_keyword(실선·chart) | 산업 선택 | 고객 언어의 화두 |
| 감성 평가 | SNS 게시글 감성 판정 | sns_sentiment(실선·chart) | 산업 선택 | 평판 방향 |
| HTML 종합 리포트 | 자립형 리포트 | html_report(실선·html) | 부록 C | 감사 추적 |
| WDA 적합성 판정 | 4종 분석 자동 실행+판정문 | wda_run(실선·data) | 17 | 이 데이터로 뭘 할 수 있나 |
| 데이터·5P 분류·품질 표 | 원본/분류/품질 | file_upload·p5_classify(실선) | 15·16 | 데이터 신뢰 |
| 주소→좌표 정제 표 | 위경도·행정동. **지오코딩이지 지도 렌더러 아님** | address_xy(실선)·/api/geocode | 지역 산업 | 지역 데이터 준비 |
| 실조작 캡처 10장 | 시스템이 실제 돌았다는 증거 | demo/shipyard_scenes/ 5장 + 루트 5장 | 11·13·14·27·29 | 데모 신뢰(크롭·주석 필수) |

### 신규 개발 필요 — 점선 카드 (템플릿에 실재로 쓰지 않음)

| 시각물 | 상태 | 비고 |
|---|---|---|
| 표 지식그래프(table_graphic) | **점선 — 신규 개발 필요** | `/api/table-graphic` 엔드포인트는 실재(main.py:1486). 카드 배선 미완 |
| 문서 지식그래프(document_graphic) | **점선 — 신규 개발 필요** | `/api/document-graphic`(GPT-4o Vision) 실재(:1510). 카드 미완 |
| 지도 주제도(thematic_map) | **점선 — 신규 개발 필요(공수 중)** | 카드가 *"엔진 없음 · 지도 위 통계 (약 10,500줄)"* 자백(erb:3084). 지역성 없는 산업(조선·제약)에선 없어도 50p 성립하도록 슬롯을 "산업 선택"으로 설계 |
| WDA HTML 리포트(wda_report) | **점선 — 신규 개발 필요** | `/api/wda-report` 실재(:1003). p17은 wda_run(실선)으로 대체 |
| xai_var_confirm·wda_roadmap·ontology_rules·data_register·clinic/survey/policy 계열 | **점선** | 본 템플릿 50p에 미사용 |

### 정본 보유·카드 미이식 — 기획자 차트 팔레트

정본 실측: px.bar 71 / scatter 44 / pie 27 / imshow 15 / histogram 15 / treemap 10 / box 9 / violin 8 / line 7 / sunburst 6 / area 6 / density 4. **정본에는 있으나 카드 UI 미이식** — 보고서에 쓰려면 이식 또는 빌더 자체 렌더가 현실적.

### 보고서 빌더 전용 판단 차트 — 신규 개발 필요(공수 소)

토네이도(p33)·워터폴(p38)·불릿(p9·37)·간트(p42)·2×2(p34)·라인 추이(p8)·회수 그래프(p43). 전부 기존 카드 산출 숫자를 다시 그리는 것이라 HTML/CSS로 공수 소.

> **핵심 판정**: 분석 시각물은 실선 카드가 이미 충분히 낸다(ERD·KG·트리 2종·차트 4종·표). 부족한 것은 **"판단 시각물" 7종**이며 전부 공수 소. 유일한 공수 중(中) 신규는 지도 주제도.

