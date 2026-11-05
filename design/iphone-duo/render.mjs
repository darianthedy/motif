// Render canvas frames to PNG for review.
// usage: node render.mjs <page.html> <outDir> [tab:selector ...]
//   tab:selector  e.g. s15:#S15a·O  or  s15:row:S15a (the whole state row)  or  cov:#cov
import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';

const require = createRequire(process.env.PLAYWRIGHT_FROM || path.resolve('node_modules') + '/');
const { chromium } = require('playwright');

const [page_, outDir, ...targets] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1600, height: 1200 }, deviceScaleFactor: Number(process.env.SCALE || 1) });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
for (const t of targets) {
  const [tab, ...rest] = t.split(':');
  const sel = rest.join(':');
  const dark = tab.endsWith('+dark');
  const tabId = tab.replace('+dark', '');
  await page.goto('file://' + path.resolve(page_) + `?tab=${tabId}${dark ? '&dark=1' : ''}`);
  if (errors.length) { console.error(errors); process.exit(1); }
  let loc;
  if (sel.startsWith('row:')) {
    const id = sel.slice(4);
    loc = page.locator('.state-row', { has: page.locator(`.state-label b:text-is("${id}")`) });
  } else if (sel.startsWith('h2:')) {
    loc = page.locator(`#${tabId}`);
  } else loc = page.locator(`[id="${sel.replace(/^#/, '')}"]`);
  const name = `${tabId}${dark ? '-dark' : ''}-${sel.replace(/[^A-Za-z0-9]+/g, '_')}.png`;
  await loc.first().screenshot({ path: path.join(outDir, name) });
  console.log(name);
}
await browser.close();
