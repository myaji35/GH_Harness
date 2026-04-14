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

# ── 4. 언어 자동 감지 + 클라이언트 스켈레톤 생성 ──────
mkdir -p lib

GEN_FILE=""
if [ -f "package.json" ]; then
  GEN_FILE="lib/gemma.ts"
  cat > "$GEN_FILE" <<'TS'
// lib/gemma.ts — Gemma 4 E4B 클라이언트 (로컬 ollama)
// 사용: import { gemma } from "@/lib/gemma";  await gemma.generate({ prompt: "..." })

const BASE = process.env.OLLAMA_BASE_URL ?? "http://localhost:11434";
const MODEL = process.env.OLLAMA_MODEL ?? "gemma4:e4b";

type GenParams = {
  prompt: string;
  images?: string[]; // base64 인코딩 이미지 배열 (OCR용)
  system?: string;
  temperature?: number;
  maxTokens?: number;
};

export const gemma = {
  async generate({ prompt, images, system, temperature = 0.2, maxTokens = 2048 }: GenParams): Promise<string> {
    const res = await fetch(`${BASE}/api/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        prompt,
        system,
        images,
        stream: false,
        options: { temperature, num_predict: maxTokens },
      }),
    });
    if (!res.ok) throw new Error(`Gemma API ${res.status}: ${await res.text()}`);
    const data = await res.json();
    return data.response ?? "";
  },

  // OCR 전용 헬퍼
  async ocr(imagePath: string, instruction = "이 이미지에서 텍스트를 그대로 추출해. 레이아웃 순서 유지."): Promise<string> {
    const fs = await import("fs/promises");
    const buf = await fs.readFile(imagePath);
    const base64 = buf.toString("base64");
    return this.generate({ prompt: instruction, images: [base64] });
  },

  // 명함 → JSON 구조화 (Townin 유스케이스)
  async parseBusinessCard(imagePath: string): Promise<Record<string, string | null>> {
    const raw = await this.ocr(
      imagePath,
      '명함 이미지에서 JSON만 출력: {"name":..., "company":..., "title":..., "phone":..., "email":..., "address":...}. 없는 필드는 null. JSON 외 텍스트 금지.'
    );
    const match = raw.match(/\{[\s\S]*\}/);
    return match ? JSON.parse(match[0]) : {};
  },
};
TS
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
  GEN_FILE="lib/gemma.py"
  cat > "$GEN_FILE" <<'PY'
"""lib/gemma.py — Gemma 4 E4B 클라이언트 (로컬 ollama)

사용:
    from lib.gemma import gemma
    text = gemma.generate("보험 약관 요약: ...")
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


class Gemma:
    def generate(
        self,
        prompt: str,
        images: Optional[list[str]] = None,
        system: Optional[str] = None,
        temperature: float = 0.2,
        max_tokens: int = 2048,
    ) -> str:
        payload = {
            "model": MODEL,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": temperature, "num_predict": max_tokens},
        }
        if system:
            payload["system"] = system
        if images:
            payload["images"] = images
        r = requests.post(f"{BASE}/api/generate", json=payload, timeout=300)
        r.raise_for_status()
        return r.json().get("response", "")

    def ocr(self, image_path: str, instruction: str = "이 이미지에서 텍스트를 그대로 추출. 레이아웃 순서 유지.") -> str:
        b64 = base64.b64encode(Path(image_path).read_bytes()).decode()
        return self.generate(prompt=instruction, images=[b64])

    def parse_business_card(self, image_path: str) -> dict:
        raw = self.ocr(
            image_path,
            '명함 이미지에서 JSON만 출력: {"name":..., "company":..., "title":..., "phone":..., "email":..., "address":...}. 없는 필드는 null. JSON 외 텍스트 금지.',
        )
        m = re.search(r"\{[\s\S]*\}", raw)
        return json.loads(m.group(0)) if m else {}


gemma = Gemma()
PY
elif [ -f "Gemfile" ]; then
  GEN_FILE="lib/gemma.rb"
  cat > "$GEN_FILE" <<'RB'
# lib/gemma.rb — Gemma 4 E4B 클라이언트 (로컬 ollama)
# 사용: Gemma.generate("보험 약관 요약: ...")

require "net/http"
require "json"
require "base64"
require "uri"

module Gemma
  BASE  = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  MODEL = ENV.fetch("OLLAMA_MODEL", "gemma4:e4b")

  module_function

  def generate(prompt:, images: nil, system: nil, temperature: 0.2, max_tokens: 2048)
    payload = {
      model: MODEL, prompt: prompt, stream: false,
      options: { temperature: temperature, num_predict: max_tokens }
    }
    payload[:system] = system if system
    payload[:images] = images if images

    uri = URI("#{BASE}/api/generate")
    res = Net::HTTP.post(uri, payload.to_json, "Content-Type" => "application/json")
    raise "Gemma #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)["response"].to_s
  end

  def ocr(image_path, instruction: "이 이미지에서 텍스트를 그대로 추출. 레이아웃 순서 유지.")
    b64 = Base64.strict_encode64(File.binread(image_path))
    generate(prompt: instruction, images: [b64])
  end

  def parse_business_card(image_path)
    raw = ocr(image_path, instruction: '명함 이미지에서 JSON만 출력: {"name":..., "company":..., "title":..., "phone":..., "email":..., "address":...}. 없는 필드는 null. JSON 외 텍스트 금지.')
    match = raw[/\{[\s\S]*\}/]
    match ? JSON.parse(match) : {}
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
