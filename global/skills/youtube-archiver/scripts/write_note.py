#!/usr/bin/env python3
"""요약 본문을 받아 옵시디언 유튜브 노트 생성 (프론트매터·썸네일·링크 자동).
사용: python3 write_note.py <video_json> <summary_md_file>
video_json: fetch_video.py 출력. summary_md_file: 요약 본문(마크다운 섹션)."""
import sys, json, os, re, datetime
from build_moc import extract_mentions_from_text, infer_topic, inferred_actionable

vjson = json.load(open(sys.argv[1], encoding="utf-8"))
summary = open(sys.argv[2], encoding="utf-8").read().strip()

VAULT_ROOT = os.path.expanduser(os.environ.get("YOUTUBE_ARCHIVER_VAULT_ROOT", "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian"))
VAULT = os.path.join(VAULT_ROOT, "📥아카이브", "유튜브")
os.makedirs(VAULT, exist_ok=True)

vid = vjson["video_id"]
title = vjson.get("title", "제목없음")
channel = vjson.get("channel", "")
ud = vjson.get("upload_date", "")
date = f"{ud[:4]}-{ud[4:6]}-{ud[6:8]}" if len(ud) == 8 else datetime.date.today().isoformat()
views = vjson.get("view_count", 0)
method = "자막 전문(yt-dlp)" if vjson.get("has_transcript") else "설명+챕터(폴백)"
has_transcript = bool(vjson.get("has_transcript"))
try:
    duration_min = int(float(vjson.get("duration", 0) or 0) / 60 + 0.5)
except (TypeError, ValueError):
    duration_min = 0
source = vjson.get("source") or "unknown"

# 파일명 안전화 — []는 옵시디언 위키링크 문법과 충돌하므로 ()로 치환
safe = re.sub(r'[/\\:*?"<>|]', "_", title)
safe = safe.replace("[", "(").replace("]", ")").strip()
if len(safe) > 40:
    boundary = safe.rfind(" ", 0, 41)
    safe = safe[:boundary if boundary > 0 else 40].strip()
fname = f"{date}_유튜브_{safe}.md"

# === 자동 태그 도출 (제목+요약 우선, 설명은 보조) ===
strong_hay = f"{title} {summary}".lower()
weak_hay = vjson.get("description", "").lower()
tag_scores = {}
# 주제 키워드 사전 (키워드 → 태그)
TOPIC = {
    "claude code": "ClaudeCode", "claude": "Claude", "anthropic": "Anthropic",
    "hermes": "Hermes", "codex": "Codex", "gemma": "Gemma", "gpt": "GPT",
    "agent": "AI에이전트", "에이전트": "AI에이전트", "agentic": "AI에이전트",
    "self-host": "셀프호스팅", "셀프호스": "셀프호스팅", "kubernetes": "인프라",
    "design": "디자인", "디자인": "디자인", "notebooklm": "NotebookLM",
    "obsidian": "옵시디언", "graphify": "지식그래프", "knowledge": "지식관리",
    "trading": "투자", "투자": "투자", "saas": "SaaS", "crm": "CRM",
    "marketing": "마케팅", "마케팅": "마케팅", "seo": "SEO", "광고": "광고",
    "ppt": "PPT", "카드뉴스": "콘텐츠제작",
    "automat": "자동화", "자동화": "자동화", "workflow": "워크플로우",
    "opensource": "오픈소스", "open source": "오픈소스", "오픈소스": "오픈소스",
    "llm": "LLM", "mcp": "MCP", "rag": "RAG", "lora": "파인튜닝",
    "병원": "의료", "메디컬": "의료", "medical": "의료", "건축": "건축",
    "부동산": "부동산", "financ": "금융", "금융": "금융",
}
for kw, tag in TOPIC.items():
    count = strong_hay.count(kw)
    if count:
        tag_scores[tag] = tag_scores.get(tag, 0) + count
if len(tag_scores) < 2:
    for kw, tag in TOPIC.items():
        count = weak_hay.count(kw)
        if count:
            tag_scores.setdefault(tag, 0)
# 콘텐츠 유형
title_hay = title.lower()
if re.search(r"만드는 법|튜토리얼|tutorial|how to build|설치|구축", title_hay):
    tag_scores["튜토리얼"] = len(re.findall(r"만드는 법|튜토리얼|tutorial|how to build|설치|구축", title_hay))
elif re.search(r"vs |비교|리뷰|review", title_hay):
    tag_scores["리뷰"] = len(re.findall(r"vs |비교|리뷰|review", title_hay))
elif re.search(r"출시|dropped|발표|introduc|공개|new ", title_hay):
    tag_scores["뉴스"] = len(re.findall(r"출시|dropped|발표|introduc|공개|new ", title_hay))
# 언어
tag_scores["영어영상" if not re.search(r"[가-힣]", title) else "한글영상"] = 0
# 분석방식
tag_scores["자막분석" if has_transcript else "설명폴백"] = 0
# 유튜브는 항상 포함, 나머지는 strong_hay 등장 횟수 내림차순으로 최대 4개
tags = ["유튜브"] + [tag for tag, _ in sorted(tag_scores.items(), key=lambda item: item[1], reverse=True)[:4]]
topic = infer_topic(tags)
depth = "로그" if not has_transcript else ("심층" if duration_min >= 20 else "표준")
status = "지식화됨" if has_transcript else "미검증로그"
actionable = inferred_actionable(depth, title, tags)
# YAML-safe: 태그·title·channel에 특수문자([ : 등)가 있으면 파싱이 깨져 옵시디언 본문이 빈 화면이 됨
def yq(v):
    v = str(v).replace('"', "'")  # 내부 큰따옴표는 작은따옴표로
    return '"' + v + '"'
tags_yaml = "[" + ", ".join(yq(t) for t in tags) + "]"

def extract_mentions(vjson, summary):
    transcript = str(vjson.get("transcript") or "").strip()
    parts = [transcript, vjson.get("description", ""), vjson.get("title", ""), summary]
    return extract_mentions_from_text("\n".join(str(part or "") for part in parts))

mentions = extract_mentions(vjson, summary)
mentions_yaml = "[" + ", ".join(yq(mention) for mention in mentions) + "]"
mentions_source = "자막" if str(vjson.get("transcript") or "").strip() else "설명문"

_WIKILINK_STEMS = None
def resolve_wikilinks(text):
    global _WIKILINK_STEMS
    if _WIKILINK_STEMS is None:
        vault_root = os.path.dirname(os.path.dirname(VAULT))
        _WIKILINK_STEMS = {
            os.path.splitext(filename)[0].strip()
            for root, dirs, files in os.walk(vault_root)
            for filename in files if filename.endswith(".md")
        }
    removed = 0
    def replace(match):
        nonlocal removed
        target = match.group(1).strip()
        if target in _WIKILINK_STEMS:
            return match.group(0)
        removed += 1
        return target
    resolved = re.sub(r"\[\[([^\[\]]+)\]\]", replace, text)
    if removed:
        print(f"[write_note] 위키링크 {removed}개를 평문화했습니다.", file=sys.stderr)
    return resolved

summary = resolve_wikilinks(summary)

note = f"""---
title: {yq(title)}
channel: {yq(channel)}
published: {date}
archived: {datetime.date.today().isoformat()}
category: 유튜브
topic: {yq(topic)}
depth: {depth}
duration_min: {duration_min}
source: {yq(source)}
actionable: {str(actionable).lower()}
tags: {tags_yaml}
mentions: {mentions_yaml}
mentions_source: {mentions_source}
video_id: {vid}
url: https://www.youtube.com/watch?v={vid}
thumbnail: https://img.youtube.com/vi/{vid}/hqdefault.jpg
views: {views}
analysis_method: {method}
status: {status}
---

# {title}

[![썸네일](https://img.youtube.com/vi/{vid}/hqdefault.jpg)](https://www.youtube.com/watch?v={vid})

▶️ **[영상 보기](https://www.youtube.com/watch?v={vid})** · 📺 {channel} · 👁 {views:,}회

{summary}
"""
path = os.path.join(VAULT, fname)
with open(path, "w", encoding="utf-8") as f:
    f.write(note)
print(path)
