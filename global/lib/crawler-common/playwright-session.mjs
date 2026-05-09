// crawler-common/playwright-session.mjs
// 공통 Playwright 세션 헬퍼 — storageState 기반 쿠키 재사용 + 만료 감지
//
// API:
//   import { openSession, saveSession, isSessionAlive } from './playwright-session.mjs';
//   const { browser, context, page } = await openSession({ stateFile, headless });
//   const alive = await isSessionAlive(page, probeUrl, expectSelector);

import { chromium } from 'playwright';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

/**
 * 공통 브라우저 컨텍스트 오픈.
 * stateFile이 존재하면 storageState로 복원, 없으면 새 컨텍스트.
 */
export async function openSession({ stateFile, headless = true, viewport = { width: 1280, height: 900 }, locale = 'ko-KR', timezoneId = 'Asia/Seoul' } = {}) {
  const browser = await chromium.launch({ headless, args: ['--disable-blink-features=AutomationControlled'] });
  const contextOpts = {
    viewport,
    locale,
    timezoneId,
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  };
  if (stateFile && existsSync(stateFile)) {
    contextOpts.storageState = stateFile;
  }
  const context = await browser.newContext(contextOpts);
  const page = await context.newPage();
  return { browser, context, page };
}

/**
 * 현재 컨텍스트의 쿠키/스토리지를 stateFile에 저장.
 */
export async function saveSession(context, stateFile) {
  if (!stateFile) throw new Error('stateFile is required');
  mkdirSync(dirname(stateFile), { recursive: true });
  await context.storageState({ path: stateFile });
}

/**
 * 세션 살아있는지 검증.
 * probeUrl로 이동 후 expectSelector가 보이면 alive=true.
 * loginIndicator (로그인 페이지 리다이렉트 시 보이는 셀렉터)가 보이면 alive=false.
 */
export async function isSessionAlive(page, { probeUrl, expectSelector, loginIndicator, timeoutMs = 8000 } = {}) {
  try {
    await page.goto(probeUrl, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
    if (loginIndicator) {
      const loginVisible = await page.$(loginIndicator);
      if (loginVisible) return false;
    }
    if (expectSelector) {
      await page.waitForSelector(expectSelector, { timeout: timeoutMs, state: 'visible' });
    }
    return true;
  } catch {
    return false;
  }
}

/**
 * 안전 종료.
 */
export async function closeSession({ browser, context }) {
  try { await context?.close(); } catch {}
  try { await browser?.close(); } catch {}
}
