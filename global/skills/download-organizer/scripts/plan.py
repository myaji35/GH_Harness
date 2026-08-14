#!/usr/bin/env python3
"""이동 계획 생성 v3 — SMG 그룹핑 + 이름보정 + 청구서. plan.json 출력. 읽기전용."""
import os, re, datetime, unicodedata, json
from collections import Counter

DL = os.environ.get("DL_DIR", os.path.expanduser("~/Downloads"))
WORK = os.environ.get("ORGANIZER_WORK", os.path.expanduser("~/.download-organizer"))
os.makedirs(WORK, exist_ok=True)

RULES = [
    (r"등기|등록면허세|법인설립|현금영수증|납부서", "법인서류", "주식회사 가가호호/법인설립"),
    (r"Google Cloud|Google Invoice|^2848116", "청구서", "Document/청구서"),
    (r"Gemini키유출|침해사고|해킹사고", "보안사고", "Document/보안사고"),
    (r"AI데이터센터", "AI데이터센터", "Project/SMG/AI데이터센터"),
    (r"홈즈페이|Home_s_Pay|HomePay", "홈즈페이", "Project/SMG/홈즈페이"),
    (r"IFMC|RWA|STO|NPL|Bio|Medical|바이오|의료|Financial_Bio|Hybrid|Shinhan|SNUH|Heavy_Ion|Precision|nkgen|엔케이젠|bitgo|custody|KMX|CY2CODE|경영전략보고서", "의료바이오금융", "Project/SMG/의료바이오금융"),
    (r"InsureGraph", "인슈어그래프", "Project/InsureGraph"),
    (r"누리팜", "누리팜", "Project/누리팜"),
    (r"Phoenix|피닉스", "피닉스", "Project/Phoenix"),
    (r"ProofLayer|프루프레이어", "프루프레이어", "Project/ProofLayer"),
    (r"AdSense|애드센스", "애드센스", "Document/애드센스"),
    (r"Invoice|인보이스", "인보이스", "Document/인보이스"),
    (r"STK|무료초청|부스", "이벤트", "Document/이벤트"),
    (r"심티어|XimTier|Xim|도시정책SNS|무선이어폰|잔고증명|설문기반|제품기능_YX", "심티어", "Project/XimTier"),
    (r"AI 스마트|AI_5P|Y_Network_Sim", "AI분석보고서", "Document/AI분석보고서"),
    (r"회의록|아젠다|Meeting 분석", "회의록", "Document/회의록"),
    (r"내부사업계획서|종합실사보고서|검증도구|의뢰인주장|공정검증|3개사업", "실사검증", "Document/실사검증"),
    (r"Physical_Control|Digital_Trade|Integrated_Digital", "산업기술", "Document/산업기술"),
    (r"KakaoTalk_Photo|IMG_\d+", "사진", "Document/사진_미분류"),
]
MONTHS = {str(i): f"{i:02d}" for i in range(1, 13)}
norm = lambda s: unicodedata.normalize("NFC", s)

def extract_date(fname, mtime):
    m = re.search(r"[_ ](\d{2})(\d{2})(\d{2})(?:[_ ]\d{4})?(?:\.| |_|$)", fname)
    if m and "01" <= m.group(2) <= "12" and "01" <= m.group(3) <= "31":
        return f"20{m.group(1)}-{m.group(2)}-{m.group(3)}"
    m = re.search(r"(20\d{2})(\d{2})(\d{2})", fname)
    if m and "01" <= m.group(2) <= "12":
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
    m = re.search(r"20(\d{2})[.\s년]+\s*(\d{1,2})[.\s월]+\s*(\d{1,2})", fname)
    if m:
        return f"20{m.group(1)}-{MONTHS.get(m.group(2),'00')}-{m.group(3).zfill(2)}"
    return mtime

def clean_topic(fname, cat):
    base = norm(os.path.splitext(fname)[0])
    base = re.sub(r"[_ ]\d{6}(?:[_ ]\d{4})?(?:KST)?", "", base)
    base = re.sub(r"_?20\d{6}(_\d{4}(KST)?)?", "", base)  # 날짜 꼬리 (HTML 보정)
    base = re.sub(r"20\d{2}[.\s년]+\s*\d{1,2}[.\s월]+\s*\d{1,2}[일]?", "", base)
    base = re.sub(r"\(심티어\)\s*", "", base)
    base = re.sub(r"\[[^\]]*\]", "", base)
    base = base.strip(" _-·")
    base = re.sub(r"\s+", "_", base)
    if base.startswith(cat + "_") or base == cat:
        base = base[len(cat):].lstrip("_")
    if len(base) > 30:
        base = base[:30].rstrip("_")
    # 회의록 등 빈 이름 보정: 카테고리명 자체를 주제로
    if not base:
        base = cat if cat != "회의록" else "회의록"
    return base

plan = []
for f in sorted(os.listdir(DL)):
    path = os.path.join(DL, f)
    if not os.path.isfile(path) or f.startswith("."):
        continue
    fn = norm(f)
    ext = os.path.splitext(fn)[1].lower().lstrip(".")
    mtime = datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat()
    # 청구서 특수처리: Spotlight title 활용
    cat, dest = "미분류", "Document/미분류"
    matchsrc = fn
    if fn.startswith("2848116"):
        matchsrc = "Google Cloud Invoice " + fn
    for pat, c, d in RULES:
        if re.search(pat, matchsrc, re.IGNORECASE):
            cat, dest = c, d
            break
    date = extract_date(fn, mtime)
    topic = clean_topic(fn, cat)
    if fn.startswith("2848116"):
        topic = "GoogleCloud_5월"
    newname = f"{date}_{cat}_{topic}.{ext}"
    plan.append({"orig": fn, "new": newname, "cat": cat, "dest": dest})

with open(os.path.join(WORK, "plan.json"), "w") as fp:
    json.dump(plan, fp, ensure_ascii=False, indent=2)

cc = Counter(p["cat"] for p in plan)
print(f"총 {len(plan)}개 이동 계획 생성 | 미분류 {cc.get('미분류',0)}개\n")
# 이름 보정 하이라이트 (HTML 꼬리, 회의록)
print("=== 이름 보정 확인 (이전 문제 항목) ===")
for p in plan:
    if p["orig"].endswith(".html") or "회의록" in p["cat"] or "청구서" in p["cat"]:
        print(f"  {p['orig'][:45]:45s} → {p['new']}")
print(f"\n미분류 남은 것: {[p['orig'] for p in plan if p['cat']=='미분류']}")
