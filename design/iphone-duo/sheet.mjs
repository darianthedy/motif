// Combine PNGs into one contact sheet: node sheet.mjs out.png height img1 img2 ...
// With --pairs, images go two by two (a capture, then its mockup frame), each pair
// captioned with the first image's name and wrapped onto rows (D09's capture sheets).
import { createRequire } from 'node:module';
import path from 'node:path';
const require = createRequire(process.env.PLAYWRIGHT_FROM || path.resolve('node_modules') + '/');
const { chromium } = require('playwright');
const [out, h, ...rest] = process.argv.slice(2);
const pairs = rest[0] === '--pairs';
const imgs = pairs ? rest.slice(1) : rest;
const width = 2400;
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: pairs ? width : 800, height: 600 } });
const fs = await import('node:fs');
const tmp = path.join(path.dirname(path.resolve(out)), '.sheet.html');
const img = (i) => `<img src="file://${path.resolve(i)}" style="height:${h}px">`;
let body;
if (pairs) {
  const items = [];
  for (let n = 0; n + 1 < imgs.length; n += 2) {
    const name = path.basename(imgs[n]).replace(/\.png$/, '');
    items.push(`<figure style="margin:0;display:flex;flex-direction:column;gap:4px"><figcaption style="font:600 18px -apple-system,system-ui,sans-serif">${name} · capture | mockup</figcaption><div style="display:flex;gap:8px;align-items:flex-start">${img(imgs[n])}${img(imgs[n + 1])}</div></figure>`);
  }
  body = `<div id=s style="display:flex;flex-wrap:wrap;gap:24px;padding:12px;width:${width - 24}px;box-sizing:border-box">${items.join('')}</div>`;
} else {
  body = `<div id=s style="display:inline-flex;gap:12px;padding:8px">${imgs.map(img).join('')}</div>`;
}
fs.writeFileSync(tmp, `<body style="margin:0;background:#fff">${body}</body>`);
await p.goto('file://' + tmp); await p.waitForLoadState('networkidle');
await p.locator('#s').screenshot({ path: out }); await b.close();
fs.unlinkSync(tmp);
