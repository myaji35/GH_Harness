#!/bin/bash
# gemma-setup.sh — "gemma 사용하자" 트리거
# 현재 프로젝트에 Gemma 4 E4B 연동 스켈레톤을 즉시 설치한다.
#
# 실행: bash .claude/hooks/gemma-setup.sh
#
# 산출:
#   1. ollama 서버 기동 (E_SSD 모델 경로)
#   2. gemma4:e4b 모델 존재 검증
#   3. .env.local에 OLLAMA_BASE_URL, OLLAMA_MODEL 추가 (중복 방지)
#   4. 프로젝트 언어 자동 감지 → lib/gemma.{ts,py,rb} 클라이언트 스켈레톤 생성
#   5. docs/GEMMA_USAGE.md 프로젝트별 가이드 생성

set -euo pipefail

OLLAMA_HOME="/Volumes/E_SSD/ollama-models"
MODEL="gemma4:e4b"
ENDPOINT="http://localhost:11434"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${BLUE}━━━ Gemma 4 E4B 프로젝트 연동 시작 ━━━${NC}"
echo "프로젝트: $(pwd)"

# ── 1. ollama 서버 기동 ───────────────────────────────
if ! pgrep -x ollama >/dev/null; then
  echo -e "${YELLOW}[1/5] ollama 서버 미기동 → 자동 시작${NC}"
  OLLAMA_MODELS="$OLLAMA_HOME" nohup ollama serve > /tmp/ollama.log 2>&1 &
  sleep 3
else
  echo -e "${GREEN}[1/5] ollama 서버 실행 중 (pid=$(pgrep ollama))${NC}"
fi

# ── 2. 모델 존재 확인 ─────────────────────────────────
if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
  echo -e "${RED}[2/5] $MODEL 미설치${NC}"
  echo "설치 명령: OLLAMA_MODELS=$OLLAMA_HOME ollama pull $MODEL"
  exit 1
fi
echo -e "${GREEN}[2/5] $MODEL 설치 확인됨${NC}"

# ── 3. .env.local 업데이트 ────────────────────────────
ENV_FILE=".env.local"
[ -f ".env" ] && ENV_FILE=".env"
touch "$ENV_FILE"

add_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}$key 이미 존재 → 유지${NC}"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
    echo -e "  ${GREEN}+ $key=$val${NC}"
  fi
}

echo -e "${BLUE}[3/5] 환경변수 기록 → $ENV_FILE${NC}"
add_env "OLLAMA_BASE_URL" "$ENDPOINT"
add_env "OLLAMA_MODEL" "$MODEL"
# 로컬 개발 기본: 30분 체류 (첫 호출 로딩 타임만 감당, 이후 즉시)
# 배포: OLLAMA_KEEP_ALIVE=-1 로 덮어쓰기 (영구 체류)
add_env "OLLAMA_KEEP_ALIVE" "30m"
# 그레이스풀: OLLAMA_ENABLED=false 로 즉시 비활성화 → 앱은 fallback 경로로 동작
add_env "OLLAMA_ENABLED" "true"
# 타임아웃: OCR 처리 여유 (기본 60초, 큰 이미지는 120000 권장)
add_env "OLLAMA_TIMEOUT_MS" "60000"

# ── 4. 언어 자동 감지 + 클라이언트 스켈레톤 생성 ──────
mkdir -p lib

GEN_FILE=""
if [ -f "package.json" ]; then
  GEN_FILE="lib/gemma.ts"
  # Townin 검증 패턴 반영: downscale + format:json + temperature:0 + safeParseJson + timeout + ENABLED 토글
  cat > "$GEN_FILE" <<'TS'
// lib/gemma.ts — Gemma 4 E4B 클라이언트 (로컬 ollama, 안전화판)
// Townin 실전 패턴 적용:
//   - 이미지 다운스케일 (1024px + JPEG 82) → 추론 3~5배 가속
//   - format:'json' + temperature:0 → 응답 안정성
//   - safeParseJson → 마크다운/트레일링 토큰 제거
//   - AbortController 타임아웃 (기본 60초)
//   - OLLAMA_ENABLED=false 로 즉시 비활성 가능 (graceful)
//
// 사용:
//   import { gemma } from "@/lib/gemma";
//   await gemma.generate({ prompt: "..." });
//   await gemma.parseBusinessCard("/path/to/card.jpg");  // sharp 필요
//   if (!gemma.isEnabled()) { /* fallback */ }

const BASE = process.env.OLLAMA_BASE_URL ?? "http://localhost:11434";
const MODEL = process.env.OLLAMA_MODEL ?? "gemma4:e4b";
const KEEP_ALIVE = process.env.OLLAMA_KEEP_ALIVE ?? "30m"; // 배포: -1
const TIMEOUT_MS = Number(process.env.OLLAMA_TIMEOUT_MS ?? 60000);
const ENABLED = (process.env.OLLAMA_ENABLED ?? "true") !== "false";

type GenParams = {
  prompt: string;
  images?: string[];
  system?: string;
  temperature?: number;
  maxTokens?: number;
  keepAlive?: string;
  timeoutMs?: number;
  formatJson?: boolean;
};

function safeParseJson(text: string): Record<string, unknown> | null {
  const stripped = text.replace(/^```json?\s*/i, "").replace(/```\s*$/i, "").trim();
  try {
    const obj = JSON.parse(stripped);
    return obj && typeof obj === "object" ? obj : null;
  } catch {
    const m = stripped.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try { return JSON.parse(m[0]); } catch { return null; }
  }
}

export const gemma = {
  isEnabled(): boolean {
    return ENABLED;
  },

  async ping(): Promise<boolean> {
    try {
      const r = await fetch(`${BASE}/api/tags`, { signal: AbortSignal.timeout(2000) });
      return r.ok;
    } catch {
      return false;
    }
  },

  async generate(params: GenParams): Promise<string> {
    if (!ENABLED) throw new Error("Gemma disabled (OLLAMA_ENABLED=false)");
    const { prompt, images, system, temperature = 0, maxTokens = 2048,
            keepAlive = KEEP_ALIVE, timeoutMs = TIMEOUT_MS, formatJson = false } = params;

    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const body: Record<string, unknown> = {
        model: MODEL,
        prompt,
        stream: false,
        keep_alive: keepAlive,
        options: { temperature, num_predict: maxTokens },
      };
      if (system) body.system = system;
      if (images && images.length) body.images = images;
      if (formatJson) body.format = "json";

      const res = await fetch(`${BASE}/api/generate`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
      if (!res.ok) throw new Error(`Gemma HTTP ${res.status}: ${await res.text()}`);
      const data = await res.json();
      return (data.response ?? "").trim();
    } finally {
      clearTimeout(timer);
    }
  },

  async generateJson<T = Record<string, unknown>>(params: GenParams): Promise<T | null> {
    const raw = await this.generate({ ...params, formatJson: true });
    return safeParseJson(raw) as T | null;
  },

  // OCR 전용 (텍스트 추출)
  async ocr(imagePath: string, instruction?: string): Promise<string> {
    const base64 = await downscaleToBase64(imagePath);
    return this.generate({
      prompt: instruction ?? "이 이미지에서 텍스트를 그대로 추출해. 레이아웃 순서 유지.",
      images: [base64],
      temperature: 0,
    });
  },

  // 명함 파싱 (Townin 프롬프트 이식)
  async parseBusinessCard(imagePath: string): Promise<Record<string, string | null> | null> {
    const base64 = await downscaleToBase64(imagePath);
    const prompt = `You are a Korean business card (명함) OCR parser.
Analyze the provided business card image and extract fields into JSON.
Respond ONLY with a single valid JSON object. No markdown, no explanation.
If a field is not present, use null.

Schema: {
  "businessNumber": "NNN-NN-NNNNN or null",
  "businessName": "상호명 or null",
  "ownerName": "대표자명 or null",
  "phone": "전화번호 or null",
  "address": "주소 or null",
  "email": "이메일 or null",
  "fax": "팩스 or null",
  "industry": "업종/업태 or null"
}`;
    return this.generateJson({ prompt, images: [base64], temperature: 0 });
  },
};

// sharp 선택적 의존 — 설치 안 되어 있으면 원본 전송
async function downscaleToBase64(imagePath: string): Promise<string> {
  const fs = await import("fs/promises");
  const buf = await fs.readFile(imagePath);
  try {
    // @ts-ignore dynamic optional
    const sharp = (await import("sharp")).default;
    const out = await sharp(buf).rotate()
      .resize({ width: 1024, height: 1024, fit: "inside", withoutEnlargement: true })
      .jpeg({ quality: 82, mozjpeg: true }).toBuffer();
    return out.toString("base64");
  } catch {
    return buf.toString("base64"); // sharp 없으면 원본
  }
}
TS
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
  GEN_FILE="lib/gemma.py"
  cat > "$GEN_FILE" <<'PY'
"""lib/gemma.py — Gemma 4 E4B 클라이언트 (로컬 ollama, 안전화판)

Townin 검증 패턴:
- Pillow 다운스케일 (1024px JPEG 82) → 추론 3~5배 가속
- format='json' + temperature=0 → 결정적 응답
- safe_parse_json → 마크다운/트레일링 제거
- requests 타임아웃 + OLLAMA_ENABLED 토글 (graceful degradation)

사용:
    from lib.gemma import gemma
    if not gemma.is_enabled(): ...  # fallback
    text = gemma.generate(prompt="보험 약관 요약: ...")
    card = gemma.parse_business_card("card.jpg")
"""

import base64
import json
import os
import re
from pathlib import Path
from typing import Optional

import requests

BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
MODEL = os.environ.get("OLLAMA_MODEL", "gemma4:e4b")
KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "30m")  # 배포: "-1"
TIMEOUT_S = int(os.environ.get("OLLAMA_TIMEOUT_MS", "60000")) / 1000
ENABLED = os.environ.get("OLLAMA_ENABLED", "true").lower() != "false"


def _safe_parse_json(text: str) -> Optional[dict]:
    stripped = re.sub(r"^```json?\s*", "", text, flags=re.I)
    stripped = re.sub(r"```\s*$", "", stripped).strip()
    try:
        obj = json.loads(stripped)
        return obj if isinstance(obj, dict) else None
    except Exception:
        m = re.search(r"\{[\s\S]*\}", stripped)
        if not m:
            return None
        try:
            return json.loads(m.group(0))
        except Exception:
            return None


def _downscale_to_base64(image_path: str) -> str:
    data = Path(image_path).read_bytes()
    try:
        from io import BytesIO
        from PIL import Image  # optional

        im = Image.open(BytesIO(data))
        im.thumbnail((1024, 1024))
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        buf = BytesIO()
        im.save(buf, format="JPEG", quality=82, optimize=True)
        return base64.b64encode(buf.getvalue()).decode()
    except Exception:
        return base64.b64encode(data).decode()  # Pillow 없으면 원본


class Gemma:
    def is_enabled(self) -> bool:
        return ENABLED

    def ping(self) -> bool:
        try:
            return requests.get(f"{BASE}/api/tags", timeout=2).ok
        except Exception:
            return False

    def generate(
        self,
        prompt: str,
        images: Optional[list[str]] = None,
        system: Optional[str] = None,
        temperature: float = 0,
        max_tokens: int = 2048,
        keep_alive: Optional[str] = None,
        format_json: bool = False,
        timeout_s: Optional[float] = None,
    ) -> str:
        if not ENABLED:
            raise RuntimeError("Gemma disabled (OLLAMA_ENABLED=false)")
        payload = {
            "model": MODEL,
            "prompt": prompt,
            "stream": False,
            "keep_alive": keep_alive or KEEP_ALIVE,
            "options": {"temperature": temperature, "num_predict": max_tokens},
        }
        if system:
            payload["system"] = system
        if images:
            payload["images"] = images
        if format_json:
            payload["format"] = "json"
        r = requests.post(f"{BASE}/api/generate", json=payload, timeout=timeout_s or TIMEOUT_S)
        r.raise_for_status()
        return (r.json().get("response") or "").strip()

    def generate_json(self, **kwargs) -> Optional[dict]:
        kwargs["format_json"] = True
        return _safe_parse_json(self.generate(**kwargs))

    def ocr(self, image_path: str, instruction: Optional[str] = None) -> str:
        b64 = _downscale_to_base64(image_path)
        return self.generate(
            prompt=instruction or "이 이미지에서 텍스트를 그대로 추출. 레이아웃 순서 유지.",
            images=[b64],
            temperature=0,
        )

    def parse_business_card(self, image_path: str) -> Optional[dict]:
        b64 = _downscale_to_base64(image_path)
        prompt = (
            "You are a Korean business card (명함) OCR parser.\n"
            "Analyze the image and extract fields into JSON.\n"
            "Respond ONLY with valid JSON. No markdown. Null for missing fields.\n\n"
            'Schema: {"businessNumber":"NNN-NN-NNNNN or null","businessName":"상호명 or null",'
            '"ownerName":"대표자명 or null","phone":"전화 or null","address":"주소 or null",'
            '"email":"이메일 or null","fax":"팩스 or null","industry":"업종 or null"}'
        )
        return self.generate_json(prompt=prompt, images=[b64], temperature=0)


gemma = Gemma()
PY
elif [ -f "Gemfile" ]; then
  GEN_FILE="lib/gemma.rb"
  cat > "$GEN_FILE" <<'RB'
# lib/gemma.rb — Gemma 4 E4B 클라이언트 (로컬 ollama, 안전화판)
# Townin 검증 패턴: MiniMagick 다운스케일, format:json, temperature:0,
# safe_parse_json, Net::HTTP timeout, OLLAMA_ENABLED 토글.

require "net/http"
require "json"
require "base64"
require "uri"

module Gemma
  BASE       = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  MODEL      = ENV.fetch("OLLAMA_MODEL", "gemma4:e4b")
  KEEP_ALIVE = ENV.fetch("OLLAMA_KEEP_ALIVE", "30m") # 배포: "-1"
  TIMEOUT_S  = (ENV.fetch("OLLAMA_TIMEOUT_MS", "60000").to_i / 1000.0)
  ENABLED    = ENV.fetch("OLLAMA_ENABLED", "true").downcase != "false"

  module_function

  def enabled?
    ENABLED
  end

  def ping
    uri = URI("#{BASE}/api/tags")
    Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) do |http|
      http.get(uri.path).is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end

  def generate(prompt:, images: nil, system: nil, temperature: 0, max_tokens: 2048,
               keep_alive: nil, format_json: false, timeout_s: nil)
    raise "Gemma disabled (OLLAMA_ENABLED=false)" unless ENABLED

    payload = {
      model: MODEL, prompt: prompt, stream: false,
      keep_alive: keep_alive || KEEP_ALIVE,
      options: { temperature: temperature, num_predict: max_tokens }
    }
    payload[:system] = system if system
    payload[:images] = images if images
    payload[:format] = "json" if format_json

    uri = URI("#{BASE}/api/generate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = timeout_s || TIMEOUT_S

    req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    req.body = payload.to_json
    res = http.request(req)
    raise "Gemma HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)["response"].to_s.strip
  end

  def generate_json(**kwargs)
    raw = generate(**kwargs.merge(format_json: true))
    safe_parse_json(raw)
  end

  def ocr(image_path, instruction: nil)
    b64 = downscale_to_base64(image_path)
    generate(
      prompt: instruction || "이 이미지에서 텍스트를 그대로 추출. 레이아웃 순서 유지.",
      images: [b64], temperature: 0
    )
  end

  def parse_business_card(image_path)
    b64 = downscale_to_base64(image_path)
    prompt = <<~PROMPT
      You are a Korean business card (명함) OCR parser.
      Analyze the image and extract fields into JSON.
      Respond ONLY with valid JSON. No markdown. Null for missing.

      Schema: {"businessNumber":"NNN-NN-NNNNN or null","businessName":"상호명 or null","ownerName":"대표자명 or null","phone":"전화 or null","address":"주소 or null","email":"이메일 or null","fax":"팩스 or null","industry":"업종 or null"}
    PROMPT
    generate_json(prompt: prompt, images: [b64], temperature: 0)
  end

  def safe_parse_json(text)
    stripped = text.sub(/^```json?\s*/i, "").sub(/```\s*$/i, "").strip
    JSON.parse(stripped)
  rescue JSON::ParserError
    m = stripped[/\{[\s\S]*\}/]
    m ? (JSON.parse(m) rescue nil) : nil
  end

  def downscale_to_base64(image_path)
    data = File.binread(image_path)
    begin
      require "mini_magick"
      img = MiniMagick::Image.read(data)
      img.combine_options do |c|
        c.auto_orient
        c.resize "1024x1024>"
        c.quality "82"
      end
      Base64.strict_encode64(img.to_blob)
    rescue LoadError, StandardError
      Base64.strict_encode64(data) # MiniMagick 없거나 실패 시 원본
    end
  end
end
RB
else
  GEN_FILE=""
  echo -e "${YELLOW}[4/5] 프로젝트 언어 감지 실패 → 클라이언트 스켈레톤 스킵${NC}"
fi

if [ -n "$GEN_FILE" ]; then
  echo -e "${GREEN}[4/5] 클라이언트 생성: $GEN_FILE${NC}"
fi

# ── 5. 사용 가이드 문서 ───────────────────────────────
mkdir -p docs
cat > docs/GEMMA_USAGE.md <<EOF
# Gemma 4 E4B — 이 프로젝트에서 쓰는 법

## 상태
- 모델: \`$MODEL\` (9.6GB, Q4_K_M, 멀티모달, 128K 컨텍스트)
- 엔드포인트: \`$ENDPOINT\`
- 저장 위치: \`$OLLAMA_HOME\`
- 클라이언트: \`$GEN_FILE\`

## 운영 모드

| 환경 | \`OLLAMA_KEEP_ALIVE\` | 운영 방식 |
|---|---|---|
| **로컬 개발** | \`30m\` (기본) | \`gemma-on\` → \`gemma-warm\` → 작업 → \`gemma-off\` |
| **배포 서버** | \`-1\` (영구) | 서비스 시작 시 자동 기동, 항상 RAM 상주 |

### 로컬 토글 (alias는 ~/.zshrc에 등록됨)
\`\`\`bash
gemma-on      # 서버 기동 (~2초)
gemma-warm    # RAM 선로딩 (~15~30초, 첫 1회만)
gemma-status  # ON/OFF 확인
gemma-off     # 종료 + RAM 10GB 즉시 회수
\`\`\`

### 배포 (프로덕션)
\`.env.production\` 또는 systemd/LaunchAgent 환경변수로:
\`\`\`
OLLAMA_KEEP_ALIVE=-1
\`\`\`
→ 모델이 절대 언로드되지 않아 모든 요청에 즉시 응답.

## 서버 기동 확인
\`\`\`bash
pgrep ollama || OLLAMA_MODELS=$OLLAMA_HOME nohup ollama serve > /tmp/ollama.log 2>&1 &
\`\`\`

## 용도별 호출 패턴

### 1. PDF / 문서 OCR
1페이지씩 이미지로 변환 후 \`gemma.ocr(path)\`.
\`pdftoppm\`이나 \`poppler\`로 PDF → PNG 변환 권장.

### 2. 명함 OCR (Townin)
\`gemma.parseBusinessCard(path)\` 또는 \`gemma.parse_business_card(path)\`.
반환: \`{name, company, title, phone, email, address}\` JSON.

### 3. InsureGraph 챗봇 보조
RAG 검색 후 청크를 프롬프트에 주입:
\`\`\`
system: 보험 도메인 전문가. 한국어로 답변.
prompt: 컨텍스트:\\n{chunks}\\n\\n질문: {user_input}
\`\`\`

### 4. 의사결정 규칙
1. OCR/문서 파싱 → Gemma 4 우선 (오프라인, 비용 0)
2. 한국어 대화 품질 결정적 → Claude API 기본, Gemma fallback
3. 대량 배치 → Gemma 1차 필터 후 중요 건만 Claude 승급

## 트러블슈팅
- \`ollama list\`에 모델 없음 → \`OLLAMA_MODELS=$OLLAMA_HOME ollama pull $MODEL\`
- 서버 응답 없음 → \`lsof -ti:11434\` 로 포트 확인, 기존 프로세스 kill 후 재기동
- 이미지 OCR 느림 → \`options.num_ctx\` 낮추기, 이미지 해상도 2000px 이하로 축소
EOF
echo -e "${GREEN}[5/5] 가이드 생성: docs/GEMMA_USAGE.md${NC}"

echo ""
echo -e "${GREEN}━━━ Gemma 4 E4B 연동 완료 ━━━${NC}"
echo "다음 단계:"
echo "  - 클라이언트 import: $GEN_FILE"
echo "  - 사용 가이드: docs/GEMMA_USAGE.md"
echo "  - 간단 테스트: echo '안녕' | ollama run $MODEL"
