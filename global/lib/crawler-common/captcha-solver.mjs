// captcha-solver.mjs — 이미지 CAPTCHA를 Anthropic Claude Vision으로 풀이
//
// 사용법:
//   import { solveCaptchaImage } from './captcha-solver.mjs';
//   const text = await solveCaptchaImage(pngBuffer);  // → "4F2X9"
//
// 환경변수: ANTHROPIC_API_KEY (필수)
//
// 한계: reCAPTCHA v2/v3 (Google)는 행동 패턴 분석 → 풀이 시도 금지 (계정 잠김)
//        풀 수 있는 것: 단순 이미지 영문/숫자 CAPTCHA (4~6자 텍스트형)

const MODEL = process.env.CAPTCHA_MODEL || 'claude-haiku-4-5-20251001';
const ENDPOINT = 'https://api.anthropic.com/v1/messages';

/**
 * @param {Buffer} pngBuffer  CAPTCHA 이미지 (PNG)
 * @param {object} opts
 * @param {string} opts.charset  'alnum' (기본) | 'digit' | 'alpha'
 * @param {number} opts.length   예상 글자 수 (검증용, 0이면 무시)
 * @returns {Promise<string>}
 */
export async function solveCaptchaImage(pngBuffer, { charset = 'alnum', length = 0 } = {}) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY 환경변수 필요');

  const charsetHint = {
    alnum: '영문자(대소문자) 또는 숫자',
    digit: '숫자만',
    alpha: '영문자만',
  }[charset] || '영문자 또는 숫자';

  const lengthHint = length > 0 ? `정확히 ${length}글자` : '보통 4~6글자';

  const prompt = [
    `이 이미지는 보안 CAPTCHA입니다. ${charsetHint}로 구성된 ${lengthHint} 텍스트를 인식해주세요.`,
    `규칙:`,
    `- 결과만 한 줄로 출력 (설명 금지)`,
    `- 공백/특수문자 제거`,
    `- 대소문자는 보이는 대로 유지`,
    `- 확신 없으면 추측하지 말고 "UNREADABLE" 출력`,
  ].join('\n');

  const body = {
    model: MODEL,
    max_tokens: 32,
    messages: [{
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: pngBuffer.toString('base64') } },
        { type: 'text', text: prompt },
      ],
    }],
  };

  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Vision API ${res.status}: ${errText}`);
  }
  const data = await res.json();
  const text = data?.content?.[0]?.text?.trim() || '';
  if (!text || text === 'UNREADABLE') throw new Error('CAPTCHA 인식 실패');
  // 안전 필터: 한 줄 + 비ASCII 제거
  const clean = text.split('\n')[0].replace(/[^\w]/g, '');
  if (length > 0 && clean.length !== length) {
    // 길이 안 맞으면 신뢰도 낮음 — 호출자가 재시도 결정
    throw new Error(`CAPTCHA 길이 불일치: 예상=${length} 실제=${clean.length} 값=${clean}`);
  }
  return clean;
}
