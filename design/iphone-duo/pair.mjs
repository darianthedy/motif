// Pair every captured cell with its rendered mockup frame (plan D09): renders the frames
// with render.mjs and joins each pair with sheet.mjs into one contact sheet per canvas tab
// and pose.
//
//   PLAYWRIGHT_FROM=<repo>/node_modules/ node pair.mjs <captures dir> <out dir>
//
// <captures dir> holds the capture run's artifacts: `capture-<pose>/` folders (or bare
// `<pose>/` folders) of `<cell>.png`. Writes <out>/<pose>/<canvas>-<tab>.png, and
// <out>/<pose>/missing.txt listing the drawn cells that have no capture.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { cells, POSES } from './cells.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const [root, outDir] = process.argv.slice(2);
if (!root || !outDir) { console.error('usage: node pair.mjs <captures dir> <out dir>'); process.exit(1); }
const node = (script, args) => execFileSync(process.execPath, [path.join(here, script), ...args], { stdio: ['ignore', 'pipe', 'inherit'] });

/** The folder holding a pose's PNGs, if it was captured. */
function capturesOf(pose) {
  for (const dir of [path.join(root, `capture-${pose}`, pose), path.join(root, `capture-${pose}`), path.join(root, pose)]) {
    if (fs.existsSync(dir) && fs.readdirSync(dir).some((f) => f.endsWith('.png'))) return dir;
  }
  return null;
}
// render.mjs names a frame `<tab>-<selector, non-alphanumerics as _>.png`.
const rendered = (tab, frame) => `${tab}-${('#' + frame).replace(/[^A-Za-z0-9]+/g, '_')}.png`;

let sheets = 0;
for (const pose of POSES) {
  const dir = capturesOf(pose);
  if (!dir) { console.log(`${pose}: no captures`); continue; }
  const poseOut = path.join(outDir, pose), frames = path.join(poseOut, 'frames');
  fs.mkdirSync(frames, { recursive: true });
  const plan = cells(pose);
  const found = plan.filter((c) => fs.existsSync(path.join(dir, c.id + '.png')));
  const missing = plan.filter((c) => !found.includes(c)).map((c) => c.id);
  fs.writeFileSync(path.join(poseOut, 'missing.txt'), missing.map((id) => id + '\n').join(''));
  // One render.mjs run per canvas; frames shared by several cells render once.
  for (const canvas of new Set(found.map((c) => c.canvas))) {
    const targets = [...new Set(found.filter((c) => c.canvas === canvas).map((c) => `${c.tab}:#${c.frame}`))];
    node('render.mjs', [path.join(here, canvas + '.html'), frames, ...targets]);
  }
  // One sheet per canvas tab: capture | mockup, in the canvas's row order.
  const tabs = new Map();
  for (const c of found) {
    const key = `${c.canvas}-${c.tab}`;
    if (!tabs.has(key)) tabs.set(key, []);
    tabs.get(key).push(path.join(dir, c.id + '.png'), path.join(frames, rendered(c.tab, c.frame)));
  }
  for (const [key, images] of tabs) {
    node('sheet.mjs', [path.join(poseOut, key + '.png'), '420', '--pairs', ...images]);
    sheets++;
  }
  console.log(`${pose}: ${found.length} of ${plan.length} drawn cells paired, ${tabs.size} sheets${missing.length ? `; no capture for ${missing.join(', ')}` : ''}`);
}
console.log(`${sheets} contact sheets in ${outDir}`);
