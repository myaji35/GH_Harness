#!/usr/bin/env python3
"""기존 유튜브 노트에 tags 프론트매터 소급 추가. write_note.py와 동일 로직.
사용: python3 add_tags.py  (VAULT의 유튜브 노트 전체 대상)"""
import os, re, glob

VAULT = os.path.expanduser("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian/📥아카이브/유튜브")

TOPIC = {
    "claude code": "ClaudeCode", "claude": "Claude", "anthropic": "Anthropic",
    "hermes": "Hermes", "codex": "Codex", "gemma": "Gemma", "gpt": "GPT",
    "agent": "AI에이전트", "에이전트": "AI에이전트", "agentic": "AI에이전트",
    "self-host": "셀프호스팅", "셀프호스": "셀프호스팅", "kubernetes": "인프라",
    "design": "디자인", "디자인": "디자인", "notebooklm": "NotebookLM",
    "obsidian": "옵시디언", "graphify": "지식그래프", "knowledge": "지식관리",
    "trading": "투자", "투자": "투자", "saas": "SaaS", "crm": "CRM",
    "marketing": "마케팅", "마케팅": "마케팅", "seo": "SEO", "광고": "광고",
    "ppt": "PPT", "카드뉴스": "콘텐츠제작", "영상": "영상제작", "video": "영상제작",
    "automat": "자동화", "자동화": "자동화", "workflow": "워크플로우",
    "opensource": "오픈소스", "open source": "오픈소스", "오픈소스": "오픈소스",
    "llm": "LLM", "mcp": "MCP", "rag": "RAG", "lora": "파인튜닝",
    "병원": "의료", "메디컬": "의료", "medical": "의료", "건축": "건축",
    "부동산": "부동산", "financ": "금융", "금융": "금융",
}

def derive_tags(title, body, has_cap):
    hay = f"{title} {body}".lower()
    tags = ["유튜브"]
    for kw, tag in TOPIC.items():
        if kw in hay and tag not in tags:
            tags.append(tag)
    if re.search(r"튜토리얼|how to|가이드|만드는 법|방법|tutorial|setup", hay):
        tags.append("튜토리얼")
    elif re.search(r"vs |비교|리뷰|review", hay):
        tags.append("리뷰")
    elif re.search(r"출시|dropped|발표|introduc|공개|new ", hay):
        tags.append("뉴스")
    tags.append("영어영상" if not re.search(r"[가-힣]", title) else "한글영상")
    tags.append("자막분석" if has_cap else "설명폴백")
    seen=set()
    return [t for t in tags if not (t in seen or seen.add(t))][:10]

notes = sorted(glob.glob(os.path.join(VAULT, "*.md")))
updated, skipped = 0, 0
for n in notes:
    txt = open(n, encoding="utf-8", errors="ignore").read()
    if re.search(r"^tags:", txt, re.M):
        skipped += 1; continue  # 이미 태그 있으면 스킵
    title_m = re.search(r"^title:\s*(.+)$", txt, re.M)
    title = title_m.group(1).strip() if title_m else ""
    has_cap = "자막 전문" in txt
    body = txt.split("---", 2)[-1] if txt.count("---") >= 2 else txt
    tags = derive_tags(title, body[:1500], has_cap)
    tags_line = "tags: [" + ", ".join(tags) + "]"
    # category: 유튜브 줄 다음에 tags 삽입
    new = re.sub(r"(^category:\s*유튜브\s*$)", r"\1\n" + tags_line, txt, count=1, flags=re.M)
    if new == txt:  # category 못 찾으면 date 다음
        new = re.sub(r"(^date:\s*.+$)", r"\1\n" + tags_line, txt, count=1, flags=re.M)
    if new != txt:
        open(n, "w", encoding="utf-8").write(new)
        updated += 1

print(f"태그 추가: {updated}개 / 이미있어 스킵: {skipped}개 / 총 {len(notes)}개")
