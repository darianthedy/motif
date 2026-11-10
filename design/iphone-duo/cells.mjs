// Which canvas frame each captured cell pairs with (plan §8.5, D09). No browser needed:
// the canvas scripts are loaded into a VM context and asked for their state table and
// `cellPlan`, so the capture run and the frames stay in step with the canvases.
//
//   node cells.mjs only            # {"O": "S01a,S01b,…", "IL": …}: the drawn cells per pose, for MOTIF_CAPTURE_ONLY
//   node cells.mjs plan <pose>     # one line per drawn cell: <capture id>\t<canvas>\t<tab>\t<frame id>
//
// Poses are the capture run's: O, IL, IP, FB, FT, and `iphone` (an iPhone 17, paired with
// the O frames: the same compact layout without the side bar). A cell that isn't drawn in a
// pose isn't captured there; extra captures (`S04a-sidebar` on IP) pair with their own frame,
// and the `var` tab's AX5 and Reduce Transparency frames pair with `<state>-AX5` / `<state>-RT` on O and IL.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const CANVASES = ['shell', 'lists', 'session', 'analysis', 'sheets'];
export const POSES = ['O', 'IL', 'IP', 'FB', 'FT', 'iphone'];
/** The canvas column a pose's captures pair with. */
export const column = (pose) => (pose === 'iphone' ? 'O' : pose);
/** Captures that aren't a state row of their own: capture id → [state, pose, frame id]. */
const EXTRA = [
  ['S04a-sidebar', 'S04a', 'IP', 'S04a·IP (sidebar shown)'],
  ['S11a-sidebar', 'S11a', 'IP', 'S11a·IP (sidebar shown)'],
];

function load(canvas) {
  const context = vm.createContext({ console });
  for (const file of ['kit.js', canvas + '.js']) vm.runInContext(fs.readFileSync(path.join(here, file), 'utf8'), context, { filename: file });
  const html = fs.readFileSync(path.join(here, canvas + '.html'), 'utf8');
  // Tab id → the prefixes its renderCanvas call takes.
  const tabs = [...html.matchAll(/getElementById\('(\w+)'\)\.innerHTML = renderCanvas\((.+?)\);/g)]
    .map(([, tab, args]) => [tab, [...args.matchAll(/'(S\d\d)'/g)].map((m) => m[1])]);
  const ids = vm.runInContext('STATES.map((s) => s.id)', context);
  const plan = (id, col) => vm.runInContext(`cellPlan(${JSON.stringify(id)}, ${JSON.stringify(col)})`, context) || {};
  // A state's tab: by its prefix, or a banner (S17x-S09) by its host's.
  const tabOf = (id) => {
    const host = id.includes('-') ? id.split('-')[1] : null;
    const own = tabs.find(([, prefixes]) => prefixes.some((p) => id.startsWith(p)));
    return (own || tabs.find(([, prefixes]) => host && prefixes.includes(host)) || [])[0];
  };
  // The `var` tab's system-variant frames (`S15a·O·AX5`, `S09i·IL·RT`), captured as `<state>-AX5` / `<state>-RT` (D10).
  const variants = () => [...vm.runInContext('renderVariants()', context).matchAll(/id="((S\d\d\w+)·(\w+)·(AX5|RT))"/g)]
    .map(([, frame, state, col, variant]) => ({ frame, state, col, variant }));
  return { canvas, ids, plan, tabOf, variants };
}

let loaded;
export function canvases() { return (loaded ??= CANVASES.map(load)); }

/** Every capture in a pose and the frame it pairs with. */
export function cells(pose) {
  const col = column(pose), out = [];
  for (const c of canvases()) {
    for (const id of c.ids) {
      if (!c.plan(id, col).drawn) continue;
      const tab = c.tabOf(id);
      if (!tab) throw new Error(`${id} has no tab on ${c.canvas}.html`);
      out.push({ id, canvas: c.canvas, tab, frame: `${id}·${col}` });
    }
    for (const [id, state, at, frame] of EXTRA) {
      if (at === col && c.ids.includes(state)) out.push({ id, canvas: c.canvas, tab: c.tabOf(state), frame });
    }
    for (const v of c.variants()) {
      if (v.col === col) out.push({ id: `${v.state}-${v.variant}`, canvas: c.canvas, tab: 'var', frame: v.frame });
    }
  }
  return out;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [what, pose] = process.argv.slice(2);
  if (what === 'only') {
    console.log(JSON.stringify(Object.fromEntries(POSES.map((p) => [p, cells(p).map((c) => c.id).join(',')]))));
  } else if (what === 'plan' && POSES.includes(pose)) {
    for (const c of cells(pose)) console.log([c.id, c.canvas, c.tab, c.frame].join('\t'));
  } else {
    console.error('usage: node cells.mjs only | plan <O|IL|IP|FB|FT|iphone>'); process.exit(1);
  }
}
