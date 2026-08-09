#!/usr/bin/env python3
"""옵시디언 유튜브 노트를 백필하고 주제별 MOC를 만든다."""
import argparse
import ast
import collections
import datetime as dt
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

TOPIC_MAP = [
    (("ClaudeCode",), "AI/ClaudeCode"),
    (("AI에이전트", "Hermes"), "AI/에이전트"),
    (("Claude", "Anthropic", "Codex", "Gemma", "GPT", "LLM", "MCP", "RAG", "파인튜닝"), "AI/LLM일반"),
    (("셀프호스팅", "인프라"), "개발/인프라"),
    (("오픈소스", "자동화", "워크플로우"), "개발/일반"),
    (("옵시디언", "NotebookLM", "지식그래프", "지식관리"), "지식관리"),
    (("마케팅", "SEO", "광고"), "비즈니스/마케팅"),
    (("SaaS", "CRM"), "비즈니스/SaaS"),
    (("부동산",), "부동산"), (("투자", "금융"), "금융/투자"), (("의료",), "건강"),
]

KNOWN_PRODUCTS = (
    "Claude Code", "Claude", "Codex", "Cursor", "Copilot", "Gemini", "ChatGPT", "GPT",
    "Ollama", "LM Studio", "Hermes", "OpenClaw", "Paperclip", "Multica", "LangChain",
    "LangSmith", "LangGraph", "n8n", "Zapier", "Make", "Dify", "Flowise", "CrewAI",
    "AutoGen", "MCP", "Mailchimp", "ConvertKit", "Kit", "Beehiiv", "Substack", "Ghost",
    "ActiveCampaign", "Klaviyo", "Brevo", "MailerLite", "GetResponse", "AWeber", "Flodesk",
    "EmailOctopus", "Listmonk", "Mautic", "Loops", "Resend", "Customer.io", "Omnisend",
    "Drip", "HubSpot", "Buttondown", "SendGrid", "Postmark", "Mailgun", "ConvertBox",
    "OptinMonster", "Hello Bar", "Privy", "Poptin", "MailMunch", "Leadpages", "Unbounce",
    "Instapage", "ClickFunnels", "Systeme.io", "Kajabi", "Podia", "Gumroad", "Typeform",
    "Tally", "Jotform", "Formspree", "Vercel", "Netlify", "Cloudflare", "Supabase",
    "Firebase", "Railway", "Render", "Fly.io", "Docker", "Kubernetes", "Proxmox", "Coolify",
    "Dokploy", "PostgreSQL", "Redis", "Neo4j", "Qdrant", "Pinecone", "Weaviate", "Chroma",
    "Figma", "Framer", "Webflow", "Carrd", "Canva", "Notion", "Obsidian", "Airtable",
    "Retool", "Bubble", "Softr", "Stitch", "Stripe", "Shopify", "Slack", "Discord", "Linear",
    "Jira", "Sentry", "PostHog", "Metabase", "Grafana", "Salesforce", "Zoho", "Circle",
    "Skool", "Teachable", "VibeVoice", "VALL-E", "Fish Audio", "Typecast",
    "ElevenLabs", "Whisper", "Deepgram", "AssemblyAI", "Cartesia", "Suno", "Udio",
    "Coqui", "Piper", "XTTS", "StyleTTS", "OpenVoice", "F5-TTS", "CosyVoice",
    "IndexTTS", "MaskGCT", "Superwhisper", "Wispr Flow", "Descript", "HeyGen",
    "Synthesia", "Higgsfield", "Seedance", "Deep-Live-Cam", "Roop", "FaceFusion",
    "Remotion", "HyperFrames", "Runway", "Kling", "Pika", "Sora", "Veo", "Qwen",
    "DeepSeek", "Kimi", "GLM", "Mistral", "Llama", "Grok", "Mythos",
    "Phi", "Command R", "FFmpeg", "PyTorch", "CUDA", "Gradio", "Streamlit",
    "ComfyUI", "Hugging Face", "Transformers", "vLLM", "llama.cpp", "Nous Research",
    "Pixel Agents", "OpenSeeker", "AutoClaw", "NemoClaw", "Drawbridge", "Firecrawl",
    "Apify", "Blotato", "NotebookLM",
)
PRODUCT_ALIASES = {
    "VibeVoice": ("바이브 보이스", "바이브보이스"),
    "ElevenLabs": ("일레븐랩스", "11Labs"),
    "Deep-Live-Cam": ("딥라이브캠",),
}
DOMAIN_STOPLIST = {
    "youtube.com", "youtu.be", "ytimg.com", "google.com", "gstatic.com",
    "googleusercontent.com", "github.com", "githubusercontent.com", "twitter.com", "x.com",
    "facebook.com", "instagram.com", "linkedin.com", "tiktok.com", "reddit.com",
    "wikipedia.org", "amazon.com", "apple.com", "microsoft.com", "bit.ly", "t.co",
    "goo.gl", "tinyurl.com", "lnkd.in", "discord.gg", "patreon.com",
    "buymeacoffee.com", "ko-fi.com", "ow.ly", "buff.ly", "shorturl.at",
    "naver.com", "tistory.com", "brunch.co.kr", "kakao.com", "yes24.com",
    "aladin.co.kr", "coupang.com", "gumroad.com", "skool.com", "productcamps.com",
    "teachable.com", "kajabi.com", "thinkific.com", "gyan.dev", "visualstudio.com",
}
DOMAIN_RE = re.compile(r"(?<![a-z0-9_@])(?:https?://)?(?:www\.)?([a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?)*\.(?:com|ai|io|so|dev))(?![a-z0-9-])", re.I)
_PRODUCT_PATTERNS = tuple(
    (product, re.compile(
        (r"\bVALL\-E\b" if product == "VALL-E" else
         r"(?<![A-Za-z0-9_])(?:" + "|".join(
             re.escape(alias) for alias in (product, *PRODUCT_ALIASES.get(product, ()))
         ) + r")(?![A-Za-z0-9_])"), re.I
    ))
    for product in KNOWN_PRODUCTS
)
CAMEL_RE = re.compile(r"(?<![A-Za-z0-9_])(?:[A-Z][a-z]+[A-Z][A-Za-z]*|[A-Z]{2,}[a-z]+)(?![A-Za-z0-9_])")
CAMEL_STOPLIST = {
    "AI", "API", "CPU", "GPU", "URL", "HTTP", "JSON", "PDF", "HTML", "CSS",
    "USB", "TTS", "ASR", "LLM", "MCP", "RAG", "CLI", "UI", "UX", "OS", "PC",
    "IT", "TV", "YouTube", "GitHub",
}

def extract_mentions_from_text(text):
    """사전 제품, 반복 복합어, 제한된 도메인 순으로 최대 20개를 반환한다."""
    text = str(text or "")
    product_counts = collections.Counter()
    first_seen = {}
    occupied = []
    for product, pattern in _PRODUCT_PATTERNS:
        matches = [
            match for match in pattern.finditer(text)
            if not any(match.start() < end and match.end() > start for start, end in occupied)
        ]
        if matches:
            product_counts[product] += len(matches)
            first_seen[product] = min(match.start() for match in matches)
            occupied.extend((match.start(), match.end()) for match in matches)
    products = sorted(product_counts, key=lambda item: (-product_counts[item], first_seen[item], item.lower()))

    camel_counts = collections.Counter()
    camel_first_seen = {}
    known_lower = {product.lower() for product in KNOWN_PRODUCTS}
    for match in CAMEL_RE.finditer(text):
        candidate = match.group(0)
        if candidate in CAMEL_STOPLIST or candidate.lower() in known_lower:
            continue
        camel_counts[candidate] += 1
        camel_first_seen.setdefault(candidate, match.start())
    camels = sorted(
        (item for item, count in camel_counts.items() if count >= 3),
        key=lambda item: (-camel_counts[item], camel_first_seen[item], item.lower()),
    )

    domains = []
    if len(products) < 3:
        domain_counts = collections.Counter()
        domain_first_seen = {}
        for match in DOMAIN_RE.finditer(text):
            domain = match.group(1).lower()
            if any(domain == stopped or domain.endswith("." + stopped) for stopped in DOMAIN_STOPLIST):
                continue
            if domain in known_lower:
                continue
            domain_counts[domain] += 1
            domain_first_seen.setdefault(domain, match.start())
        domains = sorted(
            domain_counts,
            key=lambda item: (-domain_counts[item], domain_first_seen[item], item),
        )[:2]
    return (products + camels + domains)[:20]

def mention_body(body):
    """프론트매터와 생성된 URL 전용 줄을 제외한 실제 노트 본문을 반환한다."""
    text = str(body or "")
    text = re.sub(r"\A---\s*\n.*?\n---\s*(?:\n|\Z)", "", text, count=1, flags=re.S)
    return "\n".join(
        line for line in text.splitlines()
        if not line.lstrip().startswith("[![썸네일](")
        and not line.lstrip().startswith("▶️ **[영상 보기](")
    )

def infer_topic(tags):
    tagset = set(tags or [])
    return next((topic for candidates, topic in TOPIC_MAP if tagset.intersection(candidates)), "기타")

def scalar(value):
    value = value.strip()
    if not value:
        return ""
    if value.startswith("[") and value.endswith("]"):
        try:
            return list(ast.literal_eval(value))
        except (ValueError, SyntaxError):
            return [x.strip().strip("'\"") for x in value[1:-1].split(",") if x.strip()]
    if value.lower() in ("true", "false"):
        return value.lower() == "true"
    return value.strip("'\"")

def parse_note(path):
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\s*\n(.*?)\n---\s*(?:\n|$)", text, re.S)
    if not match:
        return {}, text, ""
    raw = match.group(1)
    data = {}
    try:
        import yaml
        data = yaml.safe_load(raw) or {}
    except (ImportError, Exception):
        for line in raw.splitlines():
            m = re.match(r"^([\w-]+):\s*(.*)$", line)
            if m:
                data[m.group(1)] = scalar(m.group(2))
    return data, text[match.end():], raw

def tags_of(value):
    if isinstance(value, list):
        return [str(x) for x in value]
    if not value:
        return []
    return [x.strip().strip("#'\"") for x in str(value).strip("[]").split(",") if x.strip()]

def yq(value):
    return '"' + str(value).replace('"', "'") + '"'

def yaml_value(value):
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, list):
        return "[" + ", ".join(yq(x) for x in value) + "]"
    if value is None:
        return ""
    return yq(value) if any(c in str(value) for c in ":#[]{}&*!|>'\"%@`") else str(value)

def patch_frontmatter(raw, changes, additions):
    lines = raw.splitlines()
    for key, value in changes.items():
        replacement = f"{key}: {yaml_value(value)}"
        for i, line in enumerate(lines):
            if re.match(rf"^{re.escape(key)}\s*:", line):
                lines[i] = replacement
                break
    existing = {m.group(1) for line in lines if (m := re.match(r"^([\w-]+)\s*:", line))}
    pending = [(key, value) for key, value in additions.items() if key not in existing]
    mention_keys = {"mentions", "mentions_source"}
    mentions = [(key, value) for key, value in pending if key in mention_keys]
    pending = [(key, value) for key, value in pending if key not in mention_keys]
    if mentions:
        tag_index = next((i for i, line in enumerate(lines) if re.match(r"^tags\s*:", line)), len(lines) - 1)
        for offset, (key, value) in enumerate(mentions, 1):
            lines.insert(tag_index + offset, f"{key}: {yaml_value(value)}")
    lines.extend(f"{key}: {yaml_value(value)}" for key, value in pending)
    return "---\n" + "\n".join(lines) + "\n---\n\n"

def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(text)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise

def flatten_wikilinks(body, stems):
    removed = 0
    def replace(match):
        nonlocal removed
        inside = match.group(1).strip()
        target, sep, alias = inside.partition("|")
        lookup = target.split("#", 1)[0].strip()
        if lookup in stems:
            return match.group(0)
        removed += 1
        return alias.strip() if sep else target.strip()
    return re.sub(r"\[\[([^\[\]]+)\]\]", replace, body), removed

def has_transcript(data):
    return "자막" in str(data.get("analysis_method") or "")

def inferred_depth(data, body):
    if not has_transcript(data):
        return "로그", None
    try:
        duration_min = float(data.get("duration_min") or 0)
    except (TypeError, ValueError):
        duration_min = 0
    if duration_min > 0:
        return ("심층" if duration_min >= 20 else "표준"), "영상길이"
    return ("심층" if len(body) >= 2000 else "표준"), "본문길이추정"

KOREAN_ACTIONABLE_RE = re.compile(
    r"만들기|만드는|만들어|만들면|따라만들|구축|설치|세팅|셋업|하는 법|하는법|방법|가이드|튜토리얼|입문|시작하기|배우기|활용법"
)
ENGLISH_ACTIONABLE_RE = re.compile(
    r"\b(?:how\s+to|step\s+by\s+step|tutorial|guide|build|building|create|setup|set\s+up|getting\s+started|walkthrough|hands-on|diy)\b",
    re.I,
)
REVIEW_RE = re.compile(r"review|리뷰|vs\s|비교|unboxing|언박싱", re.I)

def inferred_actionable(depth, title, tags):
    if depth == "로그":
        return False
    if "튜토리얼" in tags:
        return True
    korean_matches = KOREAN_ACTIONABLE_RE.findall(title)
    english_matches = [match.group(0).lower() for match in ENGLISH_ACTIONABLE_RE.finditer(title)]
    if not korean_matches and not english_matches:
        return False
    if REVIEW_RE.search(title) and not korean_matches and set(english_matches) <= {"setup", "guide"}:
        return False
    return True

def note_record(path, data):
    tags = tags_of(data.get("tags"))
    depth = data.get("depth") or ("로그" if data.get("analysis_method") == "설명+챕터(폴백)" else "표준")
    return {"path": path, "stem": path.stem, "title": str(data.get("title") or path.stem),
            "channel": str(data.get("channel") or "알 수 없음"), "topic": str(data.get("topic") or infer_topic(tags)),
            "depth": str(depth), "tags": tags, "video_id": data.get("video_id", ""),
            "published": data.get("published") or data.get("date", ""), "views": data.get("views", 0),
            "status": data.get("status", ""), "url": data.get("url", ""),
            "actionable": data.get("actionable") is True or str(data.get("actionable", "")).lower() == "true",
            "has_transcript": data.get("analysis_method") != "설명+챕터(폴백)"}

def fmt_views(value):
    try: return f"{int(str(value).replace(',', '')):,}"
    except (ValueError, TypeError): return str(value or 0)

def moc_text(topic, notes, today):
    actionable = [n for n in notes if n["actionable"] or "튜토리얼" in n["tags"]]
    used = {n["stem"] for n in actionable}
    groups = [("🎯 실행/구축", actionable), ("📚 심층", [n for n in notes if n["depth"] == "심층" and n["stem"] not in used]),
              ("📄 표준", [n for n in notes if n["depth"] == "표준" and n["stem"] not in used])]
    logs = [n for n in notes if n["depth"] == "로그" and n["stem"] not in used]
    item = lambda n: f'- [[{n["stem"]}]] · {n["channel"]} · {fmt_views(n["views"])}회'
    body = ["---", f"title: {yq('유튜브 · ' + topic)}", "type: MOC", f"topic: {yq(topic)}", f"count: {len(notes)}",
            f"updated: {today}", 'tags: ["MOC", "유튜브"]', "---", "", f"# 유튜브 · {topic}", "", f"관련 유튜브 요약 노트를 모은 허브입니다. 총 {len(notes)}개", ""]
    for heading, members in groups:
        body += [f"## {heading}", ""] + ([item(n) for n in members] or ["- 없음"]) + [""]
    body += ["## 🗒 미검증 로그", "", "<details>", f"<summary>{len(logs)}개 보기</summary>", ""]
    body += [item(n) for n in logs] or ["- 없음"]
    channels = collections.Counter(n["channel"] for n in notes).most_common(3)
    summary = ", ".join(f"{c} {count}개" for c, count in channels)
    ratio = len([n for n in notes if n["depth"] == "로그"]) / len(notes) * 100
    body += ["", "</details>", "", f"상위 채널: {summary} · 미검증 로그 {ratio:.1f}%", ""]
    return "\n".join(body)

STOP = {"claude", "code", "ai", "the", "a", "an", "and", "or", "to", "of", "for", "in", "on", "with", "is", "this", "that", "new", "video", "유튜브", "영상", "리뷰", "review"}
def title_tokens(title):
    return {x for x in re.findall(r"[a-z0-9가-힣]+", title.lower()) if len(x) > 1 and x not in STOP}

def clusters(notes):
    sets = [title_tokens(n["title"]) for n in notes]
    parent = list(range(len(notes)))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    for i in range(len(notes)):
        for j in range(i + 1, len(notes)):
            union = sets[i] | sets[j]
            if union and len(sets[i] & sets[j]) / len(union) >= .35:
                a, b = find(i), find(j)
                if a != b: parent[b] = a
    grouped = collections.defaultdict(list)
    for i, note in enumerate(notes): grouped[find(i)].append(note)
    return [group for group in grouped.values() if len(group) >= 3]

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--backfill", action="store_true")
    parser.add_argument("--fix-actionable", action="store_true")
    parser.add_argument("--clusters", action="store_true")
    parser.add_argument("--extract-mentions", action="store_true")
    parser.add_argument("--force-mentions", action="store_true",
                        help="기존 mentions도 새 규칙으로 재계산해 덮어쓴다")
    args = parser.parse_args(argv)
    extract_mentions = args.extract_mentions or args.force_mentions
    root = Path(os.environ.get("YOUTUBE_ARCHIVER_VAULT_ROOT", "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian")).expanduser()
    youtube, moc_dir = root / "📥아카이브" / "유튜브", root / "00-MOC"
    paths = sorted(youtube.glob("*.md"))
    parsed = {p: parse_note(p) for p in paths}
    stems = {p.stem for p in root.rglob("*.md")}
    backfilled = ghosts = actionable_count = mentions_notes = mentions_total = 0
    mentions_changed = mentions_removed = 0
    mention_examples = []
    false_to_true = true_to_false = 0
    backup = None
    if (args.backfill or args.fix_actionable or extract_mentions) and paths and not args.dry_run:
        backup = root / "📥아카이브" / (".backup-유튜브-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
        try:
            backup.mkdir(parents=False)
            for path in paths: shutil.copy2(path, backup / path.name)
            if len(list(backup.glob("*.md"))) != len(paths): raise OSError("백업 파일 수 불일치")
        except Exception as exc:
            print(f"백업 실패: {exc}", file=sys.stderr); return 1
    for path in paths:
        data, body, raw = parsed[path]
        tags = tags_of(data.get("tags"))
        clean = [t for t in tags if t != "영상제작"]
        title = str(data.get("title") or path.stem)
        clean = clean[:5]
        inferred, depth_source = inferred_depth(data, body)
        depth = inferred if args.backfill else (data.get("depth") or inferred)
        old_actionable = data.get("actionable") is True or str(data.get("actionable", "")).lower() == "true"
        actionable = inferred_actionable(depth, title, clean) if (args.backfill or args.fix_actionable) else old_actionable
        if args.fix_actionable and actionable != old_actionable:
            if actionable:
                false_to_true += 1
            else:
                true_to_false += 1
        actionable_count += actionable
        additions = {"topic": infer_topic(clean), "depth": depth,
                     "status": "미검증로그" if depth == "로그" else "지식화됨", "source": "unknown", "actionable": actionable}
        if depth_source: additions["depth_source"] = depth_source
        if not data.get("published") and data.get("date"): additions["published"] = data["date"]
        mention_additions, mention_changes = {}, {}
        if extract_mentions and (args.force_mentions or "mentions" not in data):
            mentions = extract_mentions_from_text(mention_body(body))
            old_mentions = tags_of(data.get("mentions"))
            mention_values = {"mentions": mentions, "mentions_source": "노트본문"}
            mention_additions = {k: v for k, v in mention_values.items() if k not in data}
            mention_changes = {k: v for k, v in mention_values.items() if k in data and data.get(k) != v}
            mentions_notes += 1
            mentions_total += len(mentions)
            if old_mentions != mentions:
                removed_mentions = [item for item in old_mentions if item not in mentions]
                mentions_changed += 1
                mentions_removed += len(removed_mentions)
                if len(mention_examples) < 5:
                    mention_examples.append((path.name, old_mentions, mentions, len(removed_mentions)))
        new_body, removed = flatten_wikilinks(body, stems)
        changed_tags = clean != tags
        metadata_changes = {k: v for k, v in additions.items() if k in data and data.get(k) != v}
        if args.backfill and (changed_tags or new_body != body or metadata_changes or any(k not in data for k in additions) or mention_additions or mention_changes):
            backfilled += 1; ghosts += removed
            if not args.dry_run:
                changes = {"tags": clean} if changed_tags else {}
                changes.update(metadata_changes)
                changes.update(mention_changes)
                atomic_write(path, patch_frontmatter(raw, changes, {**additions, **mention_additions}) + new_body)
        elif args.fix_actionable and ("actionable" not in data or actionable != old_actionable):
            if not args.dry_run:
                changes = {"actionable": actionable, **mention_changes}
                atomic_write(path, patch_frontmatter(raw, changes, {"actionable": actionable, **mention_additions}) + body)
        elif mention_additions or mention_changes:
            if not args.dry_run:
                atomic_write(path, patch_frontmatter(raw, mention_changes, mention_additions) + body)
        if args.fix_actionable:
            data["actionable"] = actionable
    if (args.backfill or args.fix_actionable or extract_mentions) and not args.dry_run:
        parsed = {p: parse_note(p) for p in paths}
    notes = [note_record(p, parsed[p][0]) for p in paths]
    by_topic = collections.defaultdict(list)
    small = []
    for topic, group in collections.defaultdict(list).items(): pass
    raw_groups = collections.defaultdict(list)
    for note in notes: raw_groups[note["topic"]].append(note)
    for topic, group in raw_groups.items():
        (small if len(group) < 3 else by_topic[topic]).extend(group)
    if small: by_topic["기타"].extend(small)
    today = dt.date.today().isoformat()
    moc_files = {}
    for topic, group in sorted(by_topic.items()):
        path = moc_dir / f"유튜브-{topic.replace('/', '-')}.md"
        moc_files[topic] = path
        if not args.dry_run: atomic_write(path, moc_text(topic, group, today))
    dupes = clusters(notes) if args.clusters else []
    synth_files = []
    used_names = set()
    for group in dupes:
        common = collections.Counter(t for n in group for t in title_tokens(n["title"]))
        representative = sorted(common.items(), key=lambda item: (-item[1], item[0]))[:2]
        keyword = "-".join(re.sub(r"[^a-z0-9가-힣_-]", "-", token) for token, _ in representative) or "주제"
        base, serial = keyword, 2
        while keyword in used_names: keyword, serial = f"{base}-{serial}", serial + 1
        used_names.add(keyword)
        path = moc_dir / f"유튜브-종합-{keyword}.md"; synth_files.append(path)
        text = f"---\ntitle: {yq('유튜브 종합 · ' + keyword)}\ntype: MOC\nupdated: {today}\ntags: [\"MOC\", \"유튜브\", \"종합\"]\n---\n\n# 유튜브 종합 · {keyword}\n\n이 주제는 {len(group)}개 영상에서 반복 등장합니다.\n\n" + "\n".join(f'- [[{n["stem"]}]] · {n["channel"]}' for n in group) + "\n"
        if not args.dry_run: atomic_write(path, text)
    counts = collections.Counter(n["depth"] for n in notes); total = len(notes)
    pct = lambda n: (n / total * 100) if total else 0
    index = ["---", 'title: "유튜브 INDEX"', "type: MOC", f"updated: {today}", 'tags: ["MOC", "유튜브"]', "---", "", "# 유튜브 INDEX", ""]
    index += [f"- [[{path.stem}]] · {len(by_topic[topic])}개" for topic, path in moc_files.items()]
    index += ["", f"총 {total}개 · 심층 {pct(counts['심층']):.1f}% · 표준 {pct(counts['표준']):.1f}% · 로그 {pct(counts['로그']):.1f}% · 자막있음 {pct(sum(n['has_transcript'] for n in notes)):.1f}%", ""]
    index_path = moc_dir / "유튜브-INDEX.md"
    if not args.dry_run: atomic_write(index_path, "\n".join(index))
    home = moc_dir / "Home.md"
    home_change = False
    if home.exists():
        home_text = home.read_text(encoding="utf-8")
        if not re.search(r"\[\[[^\]]*유튜브[^\]]*\]\]", home_text, re.I):
            home_change = True
            if not args.dry_run:
                if backup is None:
                    backup = root / "📥아카이브" / (".backup-유튜브-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
                    backup.mkdir(parents=False)
                shutil.copy2(home, backup / "Home.md")
                atomic_write(home, home_text.rstrip() + "\n\n## 📺 유튜브 아카이브\n\n[[유튜브-INDEX]]\n")
    generated = list(moc_files.values()) + synth_files + [index_path]
    valid = stems | {p.stem for p in generated}
    broken = []
    for path in generated:
        text = (moc_text(next((t for t, p in moc_files.items() if p == path), ""), by_topic.get(next((t for t, p in moc_files.items() if p == path), ""), []), today) if args.dry_run and path in moc_files.values() else (path.read_text(encoding="utf-8") if path.exists() else ""))
        for link in re.findall(r"\[\[([^\]|]+)", text):
            if link not in valid: broken.append((path.name, link))
    if broken:
        for source, link in broken: print(f"깨진 링크: {source} -> {link}", file=sys.stderr)
        return 1
    if args.dry_run:
        cluster_summary = f", 종합노트 {len(synth_files)}개" if args.clusters else ""
        print(f"DRY-RUN: 백필 {backfilled}개, 주제 MOC {len(moc_files)}개{cluster_summary}, Home 수정 {home_change}")
    if args.fix_actionable:
        print(f"actionable 보정: false→true {false_to_true}개, true→false {true_to_false}개")
    if extract_mentions:
        print(f"mentions 소급: {mentions_notes}개 노트에 {mentions_total}개 mentions 부여")
        if args.force_mentions:
            print(f"mentions 재계산: {mentions_changed}개 노트 변경, 기존 항목 {mentions_removed}개 제거")
            for name, old, new, removed_count in mention_examples:
                print(f"  {name}: {old} -> {new} (제거 {removed_count}개)")
    cluster_summary = f", 종합노트 {len(synth_files)}개({sum(map(len, dupes))}개 노트)" if args.clusters else ""
    print(f"스캔 {total}개, 백필 {backfilled if args.backfill else 0}개, actionable {actionable_count}개, MOC {len(moc_files)}개 생성{cluster_summary}, 평문화한 유령링크 {ghosts if args.backfill else 0}개, 링크검증 통과")
    if args.backfill and actionable_count == 0:
        print("경고: actionable로 판정된 노트가 0개입니다.", file=sys.stderr)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
