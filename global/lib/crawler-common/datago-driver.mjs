// datago-driver.mjs — 공공데이터포털 Playwright 자동화 드라이버
//
// 호출:
//   node datago-driver.mjs login         (headed 1회, 사람이 SSO/CAPTCHA 통과)
//   node datago-driver.mjs sync-keys     (headless, 마이페이지 → 인증키 수집)
//   node datago-driver.mjs search <q>    (headless, 데이터셋 검색)
//   node datago-driver.mjs apply <id>    (headless, 활용 신청)
//
// 환경변수:
//   DATAGO_ID, DATAGO_PW, DATAGO_STATE_FILE, DATAGO_KEYS_FILE, DATAGO_PENDING_FILE

import { openSession, saveSession, isSessionAlive, closeSession } from './playwright-session.mjs';
import { solveCaptchaImage } from './captcha-solver.mjs';
import { writeFileSync, readFileSync, existsSync } from 'node:fs';

// ─────────────────────────────────────────────────────────────────────────────
// 봇 회피 헬퍼
// ─────────────────────────────────────────────────────────────────────────────
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const jitter = (min, max) => Math.floor(min + Math.random() * (max - min));

/** 사람처럼 한 글자씩 지연 입력 */
async function humanType(page, selector, text) {
  await page.click(selector, { delay: jitter(40, 120) });
  for (const ch of text) {
    await page.keyboard.type(ch, { delay: jitter(60, 160) });
  }
}

/** navigator.webdriver 위장 등 stealth */
async function applyStealth(context) {
  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    Object.defineProperty(navigator, 'languages', { get: () => ['ko-KR', 'ko', 'en-US', 'en'] });
    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
    window.chrome = { runtime: {} };
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 셀렉터/URL 격리 (사이트 변경 시 여기만 수정)
// ─────────────────────────────────────────────────────────────────────────────
const SITE = {
  base: 'https://www.data.go.kr',
  // 사이트 [로그인] 버튼이 가리키는 실제 진입점 (자동으로 SSO로 리다이렉트됨)
  loginEntryUrl: 'https://www.data.go.kr/uim/login/loginView.do',
  // SSO 페이지 도착 후 username/password 폼이 나타남
  // 신규 마이페이지 (2026-04 확인)
  myPageUrl: 'https://www.data.go.kr/iim/main/mypageMain.do',
  myKeysUrl: 'https://www.data.go.kr/iim/api/selectAcountList.do',
  searchUrl: (q) => `https://www.data.go.kr/tcs/dss/selectDataSetList.do?keyword=${encodeURIComponent(q)}`,
  applyUrl: (id) => `https://www.data.go.kr/iim/api/selectAPIAcountView.do?publicDataPk=${id}`,
  selectors: {
    // 실제 사이트 (2026-04 확인): name=username/password, id=inputUsername/inputPassword
    loginIdInput: '#inputUsername, input[name="username"]',
    loginPwInput: '#inputPassword, input[name="password"]',
    loginSubmit: '#login-btn, button.login-btn, button[type="submit"]',
    loggedInIndicator: 'a[href*="logout"], .logout, button:has-text("로그아웃")',
    myKeysTable: 'table tbody tr',
    searchResultRow: '.result-list li, .data-list li, table.list tbody tr',
    // CAPTCHA: name=captcha, id=captcha (필수 입력)
    captchaImage: '#captchaImg, img[src*="captcha" i], img[id*="captcha" i], img[alt*="보안" i]',
    captchaInput: '#captcha, input[name="captcha"]',
    captchaRefresh: '#captchaReload, button[onclick*="captcha" i]',
    recaptcha: 'iframe[src*="recaptcha"], iframe[src*="google.com/recaptcha"], div.g-recaptcha',
    rememberMe: '#inputRememberPassword, input[name="rememberMe"]',
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// 공통
// ─────────────────────────────────────────────────────────────────────────────
const STATE = process.env.DATAGO_STATE_FILE;
if (!STATE) { console.error('DATAGO_STATE_FILE 미설정'); process.exit(2); }

function loadJson(path, fallback) {
  if (!existsSync(path)) return fallback;
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return fallback; }
}
function saveJson(path, obj) {
  writeFileSync(path, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN — headed, 사람이 SSO/CAPTCHA 통과 후 자동 저장
// ─────────────────────────────────────────────────────────────────────────────
async function cmdLogin() {
  const { browser, context, page } = await openSession({ stateFile: null, headless: false });
  await applyStealth(context);
  console.error('[datago] 브라우저가 열렸습니다. 로그인을 완료해주세요.');
  await page.goto(SITE.loginEntryUrl, { waitUntil: 'domcontentloaded' });
  // SSO로 자동 리다이렉트되도록 잠시 대기
  await sleep(jitter(800, 1500));

  // ID/PW 자동 입력 + Remember Me 체크 (장기 쿠키 발급용)
  try {
    if (process.env.DATAGO_ID) {
      const idInput = await page.$(SITE.selectors.loginIdInput);
      if (idInput) await idInput.fill(process.env.DATAGO_ID);
    }
    if (process.env.DATAGO_PW) {
      const pwInput = await page.$(SITE.selectors.loginPwInput);
      if (pwInput) await pwInput.fill(process.env.DATAGO_PW);
    }
    // Remember Me 자동 체크 (세션 만료 늦춤)
    const remember = await page.$(SITE.selectors.rememberMe);
    if (remember) {
      const isChecked = await remember.isChecked().catch(() => false);
      if (!isChecked) await remember.check().catch(() => {});
      console.error('[datago] "아이디 저장" 체크 완료 (장기 세션)');
    }
    console.error('[datago] ID/PW 자동 입력 완료. CAPTCHA 입력 + 로그인 버튼은 직접 눌러주세요.');
  } catch (e) {
    console.error('[datago] 자동 입력 실패 (사이트 변경 가능). 수동 입력해주세요:', e.message);
  }

  // 로그인 완료 감지: data.go.kr 도메인의 세션 쿠키가 들어오는 순간 성공
  // (SSO 통과 후 메인 사이트로 세션이 전파되는 것이 진짜 로그인 완료 신호)
  console.error('[datago] 로그인 완료까지 대기 중... (최대 5분)');
  console.error('[datago] 로그인 후 data.go.kr 메인으로 자동 이동되거나, 직접 이동해주세요.');

  let loggedIn = false;
  const deadline = Date.now() + 5 * 60_000;
  while (Date.now() < deadline) {
    try {
      const cookies = await context.cookies();
      const wwwSession = cookies.find(c =>
        /\.?data\.go\.kr$/.test(c.domain) &&
        /JSESSIONID|SESSION|WMONID|SCOUTER|TS\w+/i.test(c.name)
      );
      const ssoCookie = cookies.find(c => c.name === 'SSO_COOKIE' && c.domain.includes('auth'));
      // 페이지 텍스트에 "로그아웃"이 보이면 확실
      const txtCheck = await page.evaluate(() => /로그아웃/.test(document.body?.innerText || '')).catch(() => false);
      if ((wwwSession && ssoCookie) || txtCheck) {
        loggedIn = true;
        break;
      }
    } catch {}
    await page.waitForTimeout(1500);
  }

  if (!loggedIn) {
    console.error('[datago] 로그인 감지 실패 (타임아웃). 쿠키를 저장하지 않습니다.');
    console.error('[datago] 다시 시도해주세요: datago login');
    await closeSession({ browser, context });
    process.exit(6);
  }

  // 메인 + 마이페이지 방문해서 세션 쿠키 확정 + 영속 쿠키 발급 유도
  try {
    await page.goto('https://www.data.go.kr', { waitUntil: 'domcontentloaded', timeout: 10_000 });
    await page.waitForTimeout(1500);
    await page.goto(SITE.myPageUrl, { waitUntil: 'domcontentloaded', timeout: 10_000 });
    await page.waitForTimeout(2000);
  } catch {}

  await saveSession(context, STATE);
  console.error(`[datago] ✓ 로그인 완료 + storageState 저장 → ${STATE}`);
  await closeSession({ browser, context });
}

// ─────────────────────────────────────────────────────────────────────────────
// REFRESH — L1 (자동 ID/PW) + L2 (Vision OCR CAPTCHA) 자동 갱신
// exit codes:
//   0 = 성공 (쿠키 저장됨)
//   3 = ID/PW 없음 (Keychain 비어있음)
//   4 = reCAPTCHA / SSO 감지 → L3 (사람 필요)
//   5 = 로그인 실패 (자격증명 오류 또는 사이트 변경)
// ─────────────────────────────────────────────────────────────────────────────
async function cmdRefresh() {
  const id = process.env.DATAGO_ID;
  const pw = process.env.DATAGO_PW;
  if (!id || !pw) { console.error('[datago] Keychain에 ID/PW 없음 → datago login 필요'); process.exit(3); }

  const { browser, context, page } = await openSession({ stateFile: null, headless: true });
  await applyStealth(context);

  try {
    await page.goto(SITE.loginEntryUrl, { waitUntil: 'domcontentloaded' });
    await sleep(jitter(800, 1600));  // 사람처럼 잠시 페이지 보기 (SSO 리다이렉트 포함)

    // reCAPTCHA / SSO 감지 → L3 폴백
    const recaptcha = await page.$(SITE.selectors.recaptcha);
    if (recaptcha) {
      console.error('RECAPTCHA_DETECTED');
      process.exit(4);
    }

    // 사람처럼 입력
    await humanType(page, SITE.selectors.loginIdInput, id);
    await sleep(jitter(300, 700));
    await humanType(page, SITE.selectors.loginPwInput, pw);
    await sleep(jitter(300, 700));

    // Remember Me 자동 체크 (장기 쿠키)
    const remember = await page.$(SITE.selectors.rememberMe);
    if (remember && !(await remember.isChecked().catch(() => false))) {
      await remember.check().catch(() => {});
    }

    // 이미지 CAPTCHA 감지 → L2 (Vision OCR) 시도
    const captchaImg = await page.$(SITE.selectors.captchaImage);
    if (captchaImg) {
      const captchaInput = await page.$(SITE.selectors.captchaInput);
      if (!captchaInput) {
        console.error('CAPTCHA_NO_INPUT');
        process.exit(4);
      }
      console.error('[datago] 이미지 CAPTCHA 감지 → Vision OCR 시도');
      let solved = false;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          const png = await captchaImg.screenshot({ type: 'png' });
          const text = await solveCaptchaImage(png, { charset: 'alnum' });
          console.error(`[datago] CAPTCHA 풀이 시도 ${attempt}: "${text}"`);
          await captchaInput.fill('');
          await humanType(page, SITE.selectors.captchaInput, text);
          solved = true;
          break;
        } catch (e) {
          console.error(`[datago] CAPTCHA 시도 ${attempt} 실패:`, e.message);
          // 새 이미지 요청 (refresh 버튼이 있다면)
          await captchaImg.click().catch(() => {});
          await sleep(800);
        }
      }
      if (!solved) {
        console.error('CAPTCHA_VISION_FAILED');
        process.exit(4);
      }
    }

    // 로그인 버튼 클릭
    await page.click(SITE.selectors.loginSubmit);

    // 성공 감지 (마이페이지 리다이렉트 또는 로그아웃 링크)
    await page.waitForFunction(
      (sel) => document.querySelector(sel) || /\/mypage\//.test(location.pathname),
      SITE.selectors.loggedInIndicator,
      { timeout: 15_000 }
    );

    // 사람처럼 잠시 머물기
    await sleep(jitter(1500, 3000));
    await saveSession(context, STATE);
    console.error('[datago] L1/L2 자동 갱신 성공');
  } catch (e) {
    console.error('[datago] 자동 로그인 실패:', e.message);
    await closeSession({ browser, context });
    process.exit(5);
  }
  await closeSession({ browser, context });
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC-KEYS — 마이페이지 → 인증키 전체 수집
// ─────────────────────────────────────────────────────────────────────────────
async function cmdSyncKeys() {
  const KEYS_FILE = process.env.DATAGO_KEYS_FILE;
  if (!KEYS_FILE) { console.error('DATAGO_KEYS_FILE 미설정'); process.exit(2); }

  const { browser, context, page } = await openSession({ stateFile: STATE, headless: true });
  const alive = await isSessionAlive(page, {
    probeUrl: SITE.myPageUrl,
    expectSelector: SITE.selectors.loggedInIndicator,
    timeoutMs: 10_000,
  });
  if (!alive) {
    await closeSession({ browser, context });
    console.error('[datago] 세션 만료. 다시 datago login 실행 필요.');
    process.exit(3);
  }

  // 마이페이지 → 활용신청 API 목록
  await page.goto(SITE.myKeysUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);

  // 페이지 구조 변경에 강건하도록 광범위 셀렉터로 row 추출
  const rows = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('table tbody tr').forEach((tr) => {
      const tds = Array.from(tr.querySelectorAll('td')).map(td => td.innerText.trim());
      if (tds.length >= 3) out.push(tds);
    });
    return out;
  });

  // 각 row 클릭 → 상세에서 일반/인코딩 키 추출 (간단형: 첫 페이지만, 추후 페이지네이션 추가 여지)
  const services = {};
  for (const row of rows) {
    // row[0] = 번호 또는 카테고리, row[1] = 서비스명, row[2~] = 상태/일자 등 (사이트별 상이)
    const name = (row.find(c => c.length > 5) || row[1] || '').slice(0, 80).replace(/\s+/g, '-').toLowerCase();
    if (!name) continue;
    services[name] = {
      service_id: null,           // 상세에서 보강 필요
      raw_row: row,
      status: row.find(c => /신청|승인|중지|만료/.test(c)) || 'UNKNOWN',
      encoding_key: null,         // TODO: 상세 페이지 진입 시 채움
      decoding_key: null,
      collected_at: new Date().toISOString(),
    };
  }

  // 결과 병합 저장
  const existing = loadJson(KEYS_FILE, { services: {}, last_sync: null });
  existing.services = { ...existing.services, ...services };
  existing.last_sync = new Date().toISOString();
  saveJson(KEYS_FILE, existing);

  console.error(`[datago] ${Object.keys(services).length}개 row 수집`);
  console.error('[datago] NOTE: 상세 페이지 키 추출은 사이트 구조에 따라 추가 패치 필요. 현재는 row만 캡처.');
  await closeSession({ browser, context });
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH — 데이터셋 검색
// ─────────────────────────────────────────────────────────────────────────────
async function cmdSearch(q) {
  const { browser, context, page } = await openSession({ stateFile: STATE, headless: true });
  await page.goto(SITE.searchUrl(q), { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);

  const rows = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('a[href*="fileDataSetView"], a[href*="openApiDetail"], a[href*="LinkedDataSet"]').forEach((a) => {
      const title = a.innerText.trim().slice(0, 120);
      const href = a.href;
      const m = href.match(/[?&]publicDataPk=(\d+)|\/(\d+)\?/);
      const id = m ? (m[1] || m[2]) : '';
      if (title) out.push({ id, title, href });
    });
    return out.slice(0, 50);
  });

  if (!rows.length) {
    console.log('(검색 결과 없음 — 사이트 셀렉터가 변경됐을 수 있음)');
  } else {
    console.log('ID\tTITLE\tURL');
    for (const r of rows) console.log(`${r.id}\t${r.title}\t${r.href}`);
  }
  await closeSession({ browser, context });
}

// ─────────────────────────────────────────────────────────────────────────────
// APPLY — 활용 신청 → 승인 대기 큐
// ─────────────────────────────────────────────────────────────────────────────
async function cmdApply(svcId) {
  const PENDING_FILE = process.env.DATAGO_PENDING_FILE;
  if (!PENDING_FILE) { console.error('DATAGO_PENDING_FILE 미설정'); process.exit(2); }
  if (!svcId) { console.error('서비스 ID 필요'); process.exit(2); }

  const { browser, context, page } = await openSession({ stateFile: STATE, headless: true });
  const alive = await isSessionAlive(page, {
    probeUrl: SITE.myPageUrl,
    expectSelector: SITE.selectors.loggedInIndicator,
    timeoutMs: 10_000,
  });
  if (!alive) {
    await closeSession({ browser, context });
    console.error('[datago] 세션 만료. 다시 datago login 실행 필요.');
    process.exit(3);
  }

  await page.goto(SITE.applyUrl(svcId), { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1000);

  // 신청 단계는 약관/사용목적 등 폼이 있어 자동 클릭하지 않고 큐에만 등록
  // (자동 클릭은 약관 동의 함의 + 사이트별 폼 필드가 달라 위험)
  const pending = loadJson(PENDING_FILE, { items: [] });
  pending.items.push({
    service_id: svcId,
    applied_at: new Date().toISOString(),
    status: 'QUEUED',
    note: '자동 신청은 약관 동의가 필요하므로 큐에만 등록. headed 로그인 후 직접 신청 권장.',
  });
  saveJson(PENDING_FILE, pending);
  console.error(`[datago] ${svcId} 큐 등록 완료. 직접 페이지를 열고 신청하세요: ${SITE.applyUrl(svcId)}`);
  await closeSession({ browser, context });
}

// ─────────────────────────────────────────────────────────────────────────────
// dispatch
// ─────────────────────────────────────────────────────────────────────────────
const [, , cmd, ...args] = process.argv;
const handlers = { login: cmdLogin, refresh: cmdRefresh, 'sync-keys': cmdSyncKeys, search: () => cmdSearch(args[0]), apply: () => cmdApply(args[0]) };
const fn = handlers[cmd];
if (!fn) { console.error(`unknown command: ${cmd}`); process.exit(2); }
try { await fn(); } catch (e) { console.error('[datago] FATAL:', e.message); process.exit(1); }
