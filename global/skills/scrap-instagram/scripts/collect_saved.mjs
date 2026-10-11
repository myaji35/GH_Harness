// Collect saved Instagram post details through the ego-browser Node runtime.
// Read a small JSON config and write the collected records to an absolute path.
// Run: { echo "process.env.SCRAP_IG_CONFIG = '<json>';"; cat collect_saved.mjs; } | ego-browser nodejs

const CONFIG = JSON.parse(process.env.SCRAP_IG_CONFIG || '{}');
if (!CONFIG.user || !CONFIG.out || !CONFIG.out.startsWith('/')) {
  throw new Error('SCRAP_IG_CONFIG requires user and an absolute out path');
}
const requestedLimit = Number(CONFIG.limit ?? 10);
const limit = Number.isFinite(requestedLimit) ? Math.min(30, Math.max(0, Math.floor(requestedLimit))) : 10;
const skip = new Set(Array.isArray(CONFIG.skip) ? CONFIG.skip : []);
const fs = await import('node:fs/promises');
const task = await taskSpace(CONFIG.space ?? 'collect saved Instagram posts');
const page = task.page('p1');

await page.goto(`https://www.instagram.com/${encodeURIComponent(CONFIG.user)}/saved/all-posts/`);
await page.waitForTimeout(5000);
const loginRequired = await page.evaluate(() =>
  [...document.querySelectorAll('input[name="username"], input[name="email"]')]
    .some((input) => input.getClientRects().length > 0)
);
if (loginRequired) {
  const result = { space: task.spaceId, user: CONFIG.user, login_required: true };
  await fs.writeFile(CONFIG.out, JSON.stringify(result, null, 2) + '\n', 'utf8');
  console.log(JSON.stringify(result));
} else {
  const ids = [];
  const seen = new Set();
  for (let scroll = 0; scroll <= 10 && ids.length < limit; scroll++) {
    const found = await page.evaluate(() =>
      [...document.querySelectorAll('a[href]')].map((link) => {
        const match = link.getAttribute('href')?.match(/^\/(?:p|reel)\/([^/]+)\//);
        return match?.[1] || '';
      }).filter(Boolean)
    );
    for (const id of found) {
      if (!skip.has(id) && !seen.has(id)) {
        seen.add(id);
        ids.push(id);
        if (ids.length >= limit) break;
      }
    }
    if (scroll < 10 && ids.length < limit) {
      await page.evaluate(() => window.scrollBy(0, window.innerHeight * 2));
      await page.waitForTimeout(1500);
    }
  }

  const items = [];
  for (const id of ids) {
    const url = `https://www.instagram.com/p/${id}/`;
    await page.goto(url);
    await page.waitForTimeout(3500 + Math.floor(Math.random() * 2001));
    const details = await page.evaluate(() => ({
      og_title: document.querySelector('meta[property="og:title"]')?.content || '',
      og_description: document.querySelector('meta[property="og:description"]')?.content || '',
      has_video: Boolean(document.querySelector('video')),
      datetime: document.querySelector('time[datetime]')?.getAttribute('datetime') || '',
    }));
    const match = details.og_description.match(/\blikes?,\s*.*?\bcomments?\s*-\s*([A-Za-z0-9._]+)\s*-\s*[^:]*:\s*["“]([\s\S]*)["”]/i);
    items.push({
      id, url,
      handle: match?.[1] || '',
      caption: match?.[2] || '',
      datetime: details.datetime,
      has_video: details.has_video,
      og_title: details.og_title,
      profile_link: '',
      profile_bio: '',
    });
  }

  const profiles = new Map();
  for (const handle of new Set(items.map((item) => item.handle).filter(Boolean))) {
    await page.goto(`https://www.instagram.com/${encodeURIComponent(handle)}/`);
    await page.waitForTimeout(4000);
    profiles.set(handle, await page.evaluate(() => {
      const header = document.querySelector('header');
      const links = [...(header?.querySelectorAll('a[href]') || [])];
      const profile_link = links.map((link) => {
        try {
          const href = new URL(link.href);
          const target = href.hostname === 'l.instagram.com'
            ? new URL(href.searchParams.get('u') || '') : href;
          const hostname = target.hostname.toLowerCase();
          if (!/^https?:$/.test(target.protocol) || hostname === 'instagram.com' ||
              hostname.endsWith('.instagram.com') ||
              ['threads.com', 'threads.net'].some((domain) => hostname === domain || hostname.endsWith(`.${domain}`))) return '';
          for (const key of [...target.searchParams.keys()]) {
            if (key.toLowerCase().startsWith('utm_') || ['fbclid', 'igsh', 'xmt'].includes(key.toLowerCase())) {
              target.searchParams.delete(key);
            }
          }
          return target.href;
        } catch { return ''; }
      }).find(Boolean) || '';
      return { profile_link, profile_bio: (header?.innerText || '').trim().slice(0, 300) };
    }));
  }

  for (const item of items) {
    Object.assign(item, profiles.get(item.handle) || {});
    console.log(`${item.id} ${item.handle} ${item.has_video} ${item.profile_link}`);
  }
  await fs.writeFile(CONFIG.out, JSON.stringify({
    space: task.spaceId,
    user: CONFIG.user,
    collected_at: new Date().toISOString(),
    items,
  }, null, 2) + '\n', 'utf8');
  await task.finish({ keep: [] });
}
