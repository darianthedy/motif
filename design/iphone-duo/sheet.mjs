// Combine PNGs into one contact sheet: node sheet.mjs out.png height img1 img2 ...
import { createRequire } from 'node:module';
import path from 'node:path';
const require = createRequire(process.env.PLAYWRIGHT_FROM || path.resolve('node_modules') + '/');
const { chromium } = require('playwright');
const [out, h, ...imgs] = process.argv.slice(2);
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 800, height: 600 } });
const fs = await import('node:fs');
const tmp = path.join(path.dirname(path.resolve(out)), '.sheet.html');
fs.writeFileSync(tmp, `<body style="margin:0;background:#fff"><div id=s style="display:inline-flex;gap:12px;padding:8px">${imgs.map((i) => `<img src="file://${path.resolve(i)}" style="height:${h}px">`).join('')}</div></body>`);
await p.goto('file://' + tmp); await p.waitForLoadState('networkidle');
await p.locator('#s').screenshot({ path: out }); await b.close();
