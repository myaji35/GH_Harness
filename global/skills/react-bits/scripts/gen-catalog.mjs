#!/usr/bin/env node
// React Bits 컴포넌트 목록(references/catalog.md)을 공식 llms.txt + registry.json 으로 다시 만든다.
// 이름·분류·설명·의존성만 적는다. 컴포넌트 소스는 넣지 않는다(라이선스 Commons Clause — 재배포 금지).
// 사용: node gen-catalog.mjs   (Node 18+, 어디서 실행하든 이 스킬의 references/ 에 쓴다)
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BASE = 'https://reactbits.dev';
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'references', 'catalog.md');

async function get(url, kind) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
  const text = await res.text();
  // 없는 경로도 SPA HTML 이 200 으로 온다 — 내용으로 확인
  if (text.trimStart().startsWith('<')) throw new Error(`${url} → JSON/텍스트가 아니라 HTML 이 왔다`);
  return kind === 'json' ? JSON.parse(text) : text;
}

const llms = await get(`${BASE}/llms.txt`, 'text');
const registry = await get(`${BASE}/r/registry.json`, 'json');

// llms.txt: "## 분류" 아래 "- [제목](url): 설명. CLI: `Name`." 줄. React Bits Pro 섹션은 건너뛴다.
const official = new Map();
let section = null;
for (const line of llms.split('\n')) {
  const h = line.match(/^##\s+(.+)/);
  if (h) { section = /pro|docs|cli/i.test(h[1]) ? null : h[1].trim(); continue; }
  if (!section) continue;
  const m = line.match(/^- \[[^\]]+\]\((https?:[^)]+)\):\s*(.*?)\s*CLI:\s*`([^`]+)`/);
  if (m) official.set(m[3], { category: section, url: m[1], description: m[2].trim() });
}

// registry: <Name>-<JS|TS>-<CSS|TW> 항목들을 이름별로 묶는다. 효과음은 <Name>-<JS|TS> 로 따로 모은다
const byName = new Map();
const sounds = new Set();
for (const item of registry.items ?? []) {
  const s = item.name.match(/^(Sound.+)-(JS|TS)$/);
  if (s) { sounds.add(s[1]); continue; }
  const m = item.name.match(/^(.+)-(JS|TS)-(CSS|TW)$/);
  if (!m) continue;
  const [, name, lang, style] = m;
  const e = byName.get(name) ?? { variants: new Set(), deps: new Set(), description: item.description };
  e.variants.add(`${lang}-${style}`);
  if (lang === 'TS' && style === 'TW') (item.dependencies ?? []).forEach((d) => e.deps.add(d));
  byName.set(name, e);
}

const groups = new Map();
for (const [name, e] of [...byName].sort(([a], [b]) => a.localeCompare(b))) {
  const o = official.get(name);
  const category = o?.category ?? 'Uncategorized';
  if (!groups.has(category)) groups.set(category, []);
  groups.get(category).push({ name, url: o?.url ?? '', description: o?.description || e.description || '', deps: [...e.deps], variants: [...e.variants].sort() });
}

const order = [...groups.keys()].sort((a, b) => (a === 'Uncategorized') - (b === 'Uncategorized') || a.localeCompare(b));
const esc = (s) => s.replace(/\|/g, '\\|');
let md = `# React Bits 컴포넌트 목록\n\n`;
md += `생성: ${new Date().toISOString().slice(0, 10)} · 출처 ${BASE}/llms.txt + ${BASE}/r/registry.json · 컴포넌트 ${byName.size}개\n\n`;
md += `의존성은 TS-TW 변형 기준 요약이다. 실제 설치 의존성은 받을 때 registry JSON 의 \`dependencies\` 를 따른다.\n`;
md += `변형이 4개(JS-CSS, JS-TW, TS-CSS, TS-TW) 다 있지 않은 것만 "변형" 칸에 적는다.\n`;
for (const cat of order) {
  const rows = groups.get(cat);
  md += `\n## ${cat} (${rows.length})\n\n| 이름 | 설명 | 의존성 | 변형 |\n|---|---|---|---|\n`;
  for (const r of rows) {
    const name = r.url ? `[${r.name}](${r.url})` : r.name;
    const variants = r.variants.length === 4 ? '' : r.variants.join(', ');
    md += `| ${name} | ${esc(r.description)} | ${esc(r.deps.join(', ')) || '-'} | ${variants} |\n`;
  }
}
if (sounds.size) {
  md += `\n## Sounds (${sounds.size})\n\n효과음 모듈. 변형은 JS·TS 두 가지(\`${BASE}/r/<Name>-JS\`, \`-TS\`). 재생 엔진은 \`SoundEngine\`.\n\n`;
  md += [...sounds].sort().map((n) => `\`${n}\``).join(' ') + '\n';
}
writeFileSync(OUT, md);
console.log(`catalog.md 갱신: 컴포넌트 ${byName.size}개, 분류 ${order.length}개, 효과음 ${sounds.size}개 → ${OUT}`);
