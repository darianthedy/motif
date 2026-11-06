// Shell and homes canvas (S01 Launch, S02 Sign in, S03 Account, S04 Puzzles home,
// S11 Games home, S17 Library banners on the S04 host). Plan §5, §7 (App shell).
//
// Shell: TabView (system tab bar) whose tabs each hold one NavigationSplitView.
// Compact: it collapses to a stack (O, SV). Regular: sidebar column = the home list,
// detail column = the selected collection; a board screen pushed in the detail hides
// the sidebar (.detailOnly), which is how the board canvases are drawn.

const COLS = ['O', 'IL', 'IP', 'SV', 'FB', 'FT', 'PP', 'PD'];

const STATES = [
  { id: 'S01a', t: 'Blank (before the first frame)', scr: 'launch', v: 'blank' },
  { id: 'S01b', t: 'Loading', scr: 'launch', v: 'loading' },
  { id: 'S01c', t: 'First launch offline', scr: 'launch', v: 'offline' },
  { id: 'S01d', t: 'Load error (Try Again / Sign Out)', scr: 'launch', v: 'error' },
  { id: 'S01e', t: 'Sign-out failed banner', scr: 'launch', v: 'error', banner: 'dismiss' },
  { id: 'S02a', t: 'Empty (buttons disabled)', scr: 'signin' },
  { id: 'S02b', t: 'Filled', scr: 'signin', filled: true },
  { id: 'S02c', t: 'Keyboard up', scr: 'signin', filled: true, kb: true },
  { id: 'S02d', t: 'Busy', scr: 'signin', filled: true, busy: true },
  { id: 'S02e', t: 'Wrong password', scr: 'signin', filled: true, err: true },
  { id: 'S02f', t: 'Offline', scr: 'signin', filled: true, offline: true },
  { id: 'S02g', t: 'Dev-account footer', scr: 'signin', dev: true },
  { id: 'S03a', t: 'Up to date', scr: 'account', sync: 'ok' },
  { id: 'S03b', t: 'Syncing', scr: 'account', sync: 'syncing' },
  { id: 'S03c', t: 'N waiting to upload', scr: 'account', sync: 'waiting' },
  { id: 'S03d', t: 'Offline (Sign Out disabled)', scr: 'account', sync: 'offline' },
  { id: 'S03e', t: 'Offline, N waiting', scr: 'account', sync: 'offlineWaiting' },
  { id: 'S03f', t: 'Server error', scr: 'account', sync: 'error' },
  { id: 'S03g', t: 'Nothing to reset', scr: 'account', sync: 'ok', noReset: true },
  { id: 'S03h', t: 'Reset confirmation', scr: 'account', sync: 'ok', overlay: 'reset' },
  { id: 'S03i', t: 'Dev-account footer', scr: 'account', sync: 'ok', dev: true },
  { id: 'S03j', t: 'Toast after reset', scr: 'account', sync: 'ok', toast: 'Progress reset. Every puzzle is unseen again.' },
  { id: 'S03k', t: 'Error banner', scr: 'account', sync: 'ok', errBanner: true },
  { id: 'S04a', t: 'Populated', scr: 'puzzles' },
  { id: 'S04b', t: 'No session, nothing to review', scr: 'puzzles', noSession: true },
  { id: 'S04c', t: 'Collections, no puzzles (Practice hidden)', scr: 'puzzles', noPuzzles: true },
  { id: 'S04d', t: 'Empty', scr: 'puzzles', empty: true },
  { id: 'S04e', t: 'Empty offline', scr: 'puzzles', empty: true, offline: true },
  { id: 'S04f', t: 'Offline', scr: 'puzzles', offline: true },
  { id: 'S04g', t: 'Context menu', scr: 'puzzles', overlay: 'ctx' },
  { id: 'S04h', t: 'Swipe delete', scr: 'puzzles', swipe: true },
  { id: 'S04i', t: 'Rename alert', scr: 'puzzles', overlay: 'rename' },
  { id: 'S04j', t: 'Delete confirmation', scr: 'puzzles', overlay: 'delete' },
  { id: 'S11a', t: 'Populated', scr: 'games' },
  { id: 'S11b', t: 'Empty', scr: 'games', empty: true },
  { id: 'S11c', t: 'Empty offline', scr: 'games', empty: true, offline: true },
  { id: 'S11d', t: 'New collection alert', scr: 'games', overlay: 'newcol' },
  { id: 'S11e', t: 'Context menu', scr: 'games', overlay: 'ctx' },
  { id: 'S11f', t: 'Swipe actions', scr: 'games', swipe: true },
  { id: 'S11g', t: 'Rename alert', scr: 'games', overlay: 'rename' },
  { id: 'S11h', t: 'Delete confirmation', scr: 'games', overlay: 'delete' },
  { id: 'S11i', t: 'Offline', scr: 'games', offline: true },
  { id: 'S17a-S04', t: 'Banner: offline', scr: 'puzzles', offline: true },
  { id: 'S17b-S04', t: 'Banner: offline, N waiting', scr: 'puzzles', offline: true, waiting: true },
  { id: 'S17c-S04', t: 'Banner: server error', scr: 'puzzles', banner: 'server' },
  { id: 'S17d-S04', t: 'Banner: dismissible error', scr: 'puzzles', banner: 'dismiss' },
  { id: 'S17e-S04', t: 'Toast', scr: 'puzzles', banner: 'toast' },
];
const S = Object.fromEntries(STATES.map((s) => [s.id, s]));

const DRAW = {
  IP: ['S01b', 'S01d', 'S02a', 'S02c', 'S03a', 'S04a', 'S04d', 'S11a', 'S11b', 'S17c-S04'],
  SV: ['S02a', 'S03a', 'S04a', 'S11a'],
  FB: ['S02c', 'S03a', 'S04a', 'S04i', 'S04j', 'S11a', 'S11d', 'S01d'],
  PD: ['S01b', 'S02a', 'S03a', 'S04a', 'S11a'],
};
const OVERLAY = new Set(STATES.filter((s) => s.overlay).map((s) => s.id));

function cellPlan(id, col) {
  if (col === 'O' || col === 'IL') return { drawn: true };
  if ((DRAW[col] || []).includes(id)) return { drawn: true };
  const st = S[id];
  const prim = { launch: 'S01b', signin: 'S02a', account: 'S03a', puzzles: 'S04a', games: 'S11a' }[st.scr];
  switch (col) {
    case 'IP': return OVERLAY.has(id) ? { eq: `${id}·IL`, why: 'overlay, regular (§5.5)' } : { eq: `${prim}·IP + content of ${id}·IL` };
    case 'SV': return { eq: `${id}·O`, why: 'compact width (device-checked)' };
    case 'FB': return OVERLAY.has(id) ? { eq: `${id}·IL, on one page`, why: '§5.5' } : { eq: `${prim}·FB + content of ${id}·IL` };
    case 'FT': return { eq: `${id}·IP`, why: 'no board: scrolling content may cross the fold; sheets and alerts sit below it' };
    case 'PP': return { eq: `${id}·IL`, why: 'decision 9' };
    case 'PD': return { eq: `${id}·IL`, why: 'iPad = regular layouts (D11)' };
  }
}

// Detail column on regular width: the selected collection (S06 / S12 are drawn on the Lists canvas)
function detail(st, col, y0) {
  const x = col.x + 20, w = Math.min(col.w - 40, 672);
  if (st.empty) {
    const games = st.scr === 'games';
    return abs(col.x, y0 + 120, col.w, 260, cuv(games ? 'board' : 'puzzle', games ? 'No Games Yet' : 'No Puzzles Yet', games ? 'Create a collection, then import PGN or play moves on the board.' : 'Import puzzles from text or a file to start solving.', pbtn(games ? 'New Collection' : 'Import Puzzles', { prom: true, dis: st.offline }) + (st.offline ? '<span style="font-size:13px">Importing needs a connection.</span>' : '')));
  }
  let h = '';
  if (st.scr === 'puzzles') {
    h += abs(x, y0, w, 30, `<div class="ttl">Back-rank mates</div>`);
    h += abs(x, y0 + 44, w, 110, `<div class="glist" style="padding:16px;display:flex;gap:16px;align-items:center">${ring(33).replace('class="ring"', 'class="ring big"')}<span style="display:flex;flex-direction:column;gap:2px"><b style="font-size:20px">1 of 3 solved</b><span class="lr-s" style="font-size:15px">1 to review · 1 unseen</span></span></div>`);
    h += abs(x, y0 + 170, w, 200, section('', [
      row({ lead: tile('skip', 'var(--accent)'), title: 'Resume Session', trail: '<span class="lr-v">2 left</span>' }),
      row({ lead: tile('flip', '#ff9500'), title: 'Review Mistakes', trail: '<span class="badge">1</span>' }),
      row({ lead: tile('lines', '#8e8e93'), title: 'Puzzles', trail: '<span class="lr-v">3</span>', chev: true }),
    ]));
  } else {
    h += abs(x, y0, w, 30, `<div class="ttl">Club games</div>`);
    const games = [['Me – Club friend', '1-0 · Ruy Lopez · 2026.10.12'], ['Club friend – Me', '½-½ · Caro-Kann · 2026.10.05'], ['Me – Rapid opponent', '0-1 · Sicilian · 2026.09.28'], ['Me – Club friend', '1-0 · Italian · 2026.09.21'], ['Simul game', '* · Queen\'s Gambit · 2026.09.14']];
    h += abs(x, y0 + 44, w, 330, section('', games.map(([a, b]) => row({ title: a, sub: b, chev: true }))));
  }
  return h;
}

// ---------- Composer ----------

function compose(id, k, opts = {}) {
  const st = { ...S[id], ...(opts.st || {}) };
  const gk = opts.geomKey || (k === 'SV' ? 'SVL' : k);
  const cfg = CFG[gk];
  const g = shellGeom(gk);
  let html = '';
  const fs = opts.ax5 ? 1.9 : 1;
  if (st.scr === 'launch') html += launch(st, g, cfg);
  else if (st.scr === 'signin') html += signin(st, g, cfg);
  else if (st.scr === 'account') html += account(st, g, cfg, opts);
  else html += home(st, g, cfg, fs);
  const chips = [{ text: cfg.size }];
  if (st.scr === 'puzzles' || st.scr === 'games') {
    chips.push({ text: g.overlay ? `TabView › NavigationSplitView: detail ${g.cols[0].w}; sidebar ${g.overlay.w} overlays it (${st.empty || st._sidebar ? 'columnVisibility .all' : '.detailOnly'})` : g.cols.length > 1 ? `TabView › NavigationSplitView: sidebar ${Math.round(g.cols[0].w)} + detail ${Math.round(g.cols[1].w)}` : 'TabView › NavigationSplitView (collapsed to a stack)', kind: 'ct' });
    if (g.overlay) chips.push({ text: st.empty || st._sidebar ? 'sidebar shown: no selection, or the sidebar button' : 'decision 16: detail only, sidebar button', kind: 'fix' });
    chips.push({ text: g.bars === 'side' ? 'tab bar: bottom of the side bar' : gk === 'PD' ? 'tab bar: top (iPadOS)' : 'tab bar: bottom', kind: '' });
    if (gk === 'FB') chips.push({ text: 'column boundary on the fold', kind: 'fix' });
  }
  if (st.scr === 'account') chips.push({ text: g.compact ? 'sheet · toolbarVerticalBehavior opt-out: ✕ stays in its navigation bar' : 'form sheet, centered', kind: 'ct' });
  if (st.scr === 'signin' || st.scr === 'launch') chips.push({ text: g.compact ? 'single column' : 'centered column ≤ 480 pt', kind: 'ct' });
  (opts.chips || []).forEach((c) => chips.push(c));
  return frame(opts.fid || `${id}·${k}`, gk, html, chips, { caption: opts.caption || st.t, cls: (opts.rt ? 'rt ' : '') + (opts.ax5 ? 'ax5' : '') });
}

function sideStatusOnly(cfg) {
  return cfg.side ? abs(cfg.side.edge === 'R' ? cfg.w - cfg.side.w : 0, 0, cfg.side.w, 174, `<div class="sb-time">9:41</div><div class="sb-wifi">${icon('wifi', 22)}</div>`, 'sb-status', cfg.camera ? 'padding-top:72px' : 'padding-top:30px') : statusBar(cfg);
}

function centerCol(g, cfg, w) {
  const x0 = g.contentX0, x1 = g.contentX1;
  const ww = Math.min(w, x1 - x0 - 32);
  return { x: x0 + (x1 - x0 - ww) / 2, w: ww };
}

function launch(st, g, cfg) {
  let html = sideStatusOnly(cfg);
  if (st.v === 'blank') return html;
  const c = centerCol(g, cfg, 480);
  const pageX = g.k === 'FB' ? { x: 515.5, w: 331.5 } : c; // FB: on the right page
  const cy = cfg.h / 2 - 120;
  if (st.v === 'loading') html += abs(pageX.x, cfg.h / 2 - 30, pageX.w, 60, `<div class="cuv"><span class="spinner" style="display:inline-block;width:26px;height:26px"></span><div style="margin-top:8px">Loading your library…</div></div>`);
  if (st.v === 'offline') html += abs(pageX.x, cy, pageX.w, 200, cuv('wifiSlash', 'You’re Offline', 'This device has no copy of your library yet. Connect once to download it.'));
  if (st.v === 'error') html += abs(pageX.x, cy, pageX.w, 260, cuv('warn', 'Couldn’t Load Your Library', 'The server took too long to answer.', pbtn('Try Again', { prom: true }) + pbtn('Sign Out', { red: true })));
  if (st.banner) html += transient(g, cfg, 'dismiss', 'Couldn’t sign out. Check your connection and try again.');
  return html;
}

function signin(st, g, cfg) {
  let html = sideStatusOnly(cfg);
  const kbH = st.kb ? (g.compact ? 313 : 289) : 0;
  const c = g.k === 'FB' && st.kb ? { x: 515.5, w: 331.5 } : centerCol(g, cfg, 480);
  const headH = st.kb ? 70 : 190;
  const formH = 96 + (st.err ? 40 : 0) + (st.dev ? 60 : 0) + (st.offline ? 40 : 0) + 24 + 50 + 44;
  let y = st.kb ? Math.max(g.top + 16, cfg.h - kbH - 12 - headH - formH) : Math.max(g.top + 30, (cfg.h - cfg.bottom - headH - formH) / 2);
  const head = st.kb
    ? `<div style="text-align:center"><div style="font-size:28px;font-weight:700">Motif</div></div>`
    : `<div style="display:flex;justify-content:center"><span class="logo">${icon('board', 40, 1.6)}</span></div><div style="text-align:center;font-size:34px;font-weight:700;margin-top:12px">Motif</div><div style="text-align:center;color:var(--label2);font-size:15px;margin-top:6px">Your chess puzzles and games, the same on every device.</div>`;
  html += abs(c.x, y, c.w, headH, head); y += headH;
  const email = st.filled ? 'sample@motif.local' : '<span style="color:var(--label3)">Email</span>';
  const pw = st.filled ? '••••••••' + (st.kb ? '<span class="caret" style="display:inline-block;width:2px;height:20px;background:var(--accent);vertical-align:-4px"></span>' : '') : '<span style="color:var(--label3)">Password</span>';
  let form = `<div class="glist"><div class="gl-row">${email}</div><div class="gl-row">${pw}</div></div>`;
  if (st.err) form += `<div style="color:var(--red-text);font-size:15px;padding:10px 16px;display:flex;gap:6px;align-items:center">${icon('warn', 16)}Wrong email or password.</div>`;
  if (st.offline) form += `<div style="color:var(--label2);font-size:13px;padding:10px 16px">You’re offline. Signing in needs a connection.</div>`;
  if (st.dev) form += `<div class="sec-f">No database is configured, so any email and password will do. This library stays on this device.</div>`;
  const dis = !st.filled || st.offline;
  form += `<div style="margin-top:24px;display:flex;flex-direction:column;gap:6px;align-items:stretch"><span class="btn prom" style="flex:none;${dis ? 'opacity:.4' : ''}">${st.busy ? '<span class="spinner" style="border-color:rgba(255,255,255,.4);border-top-color:#fff"></span>' : 'Sign In'}</span><span class="btn" style="color:var(--accent);${dis ? 'opacity:.4' : ''}">Create Account</span></div>`;
  html += abs(c.x, y, c.w, formH, form);
  if (kbH && g.compact) html += abs(0, cfg.h - kbH, cfg.w, kbH, `<div style="padding:14px;color:var(--label2);font-size:13px;text-align:center">Keyboard 313 pt</div>`, 'kbd');
  else if (kbH) { const kl = '<div style="padding:14px;color:var(--label2);font-size:13px;text-align:center">Split keyboard 289 pt</div>'; html += abs(0, cfg.h - kbH, 360, kbH, kl, 'kbd') + abs(cfg.w - 360, cfg.h - kbH, 360, kbH, kl, 'kbd'); }
  return html;
}

function account(st, g, cfg, opts) {
  // Presented over Puzzles home
  let html = home({ scr: 'puzzles' }, g, cfg, 1) + dim(cfg);
  let x, y, w, h;
  if (g.compact) { x = 8 + (g.k === 'SVL' ? 84 : 0); w = (g.k === 'SVL' ? 455.5 - 84 : g.k === 'SVR' ? 371.5 : 466) - 16; y = 24; h = cfg.h - y; if (g.k === 'SVR') x = 13.5 + 8; }
  else if (g.k === 'FB') { x = 8; w = 440; y = 30; h = cfg.h - 60; }
  else { w = Math.min(653, cfg.w - 40); x = (cfg.w - (cfg.side ? cfg.side.w : 0) - w) / 2; y = g.top + 30; h = cfg.h - y - 30; }
  const syncRow = {
    ok: `${icon('checkCircle', 20)}<span>Up to date</span>`,
    syncing: `<span class="spinner"></span><span>Syncing…</span>`,
    waiting: `${icon('flip', 20)}<span>2 results waiting to upload</span>`,
    offline: `${icon('wifiSlash', 20)}<span style="color:var(--label2)">Offline</span>`,
    offlineWaiting: `${icon('wifiSlash', 20)}<span style="color:var(--label2)">Offline · 2 results waiting</span>`,
    error: `${icon('warn', 20)}<span style="display:flex;flex-direction:column"><span>Couldn't reach the server</span><span class="lr-s">The request timed out.</span></span>`,
  }[st.sync];
  const off = st.sync === 'offline' || st.sync === 'offlineWaiting';
  let body = `<div class="glist" style="display:flex;gap:12px;align-items:center;padding:14px 16px"><span class="avatar big">S</span><span style="display:flex;flex-direction:column"><b>sample@motif.local</b><span class="lr-s" style="font-size:15px">Signed in</span></span></div>`;
  body += section('Sync', [`<div class="lrow sync ${st.sync}">${syncRow}</div>`], { footer: st.dev ? 'No database is configured, so this library stays on this device.' : '' });
  body += section('Progress', [`<div class="lrow${st.overlay === 'reset' ? ' lifted' : ''}" style="color:var(--red);${st.noReset ? 'opacity:.4' : ''}">Reset Puzzle Progress…</div>`], { footer: 'Forgets every attempt on every device: solved, mistakes and sessions in progress. Your puzzles and collections stay.' });
  body += section('', [`<div class="lrow" style="color:var(--red);${off ? 'opacity:.4' : ''}">Sign Out</div>`], { footer: off ? 'Signing out needs a connection.' : '' });
  body += section('Acknowledgements', [`<div class="lrow">Evaluation by Stockfish, licensed under GPL-3.0</div>`, `<div class="lrow" style="color:var(--accent)">Stockfish Source</div>`]);
  // ✕ stays in the sheet's own navigation bar (single toolbar item opts out of the vertical bar)
  const head = `<div class="sh-head" style="justify-content:flex-start;padding-left:20px"><span class="sh-title" style="font-size:17px">Account</span>${abs(w - 56, 10, 44, 44, icon('xmark', 19), 'tb')}</div>`;
  html += abs(x, y, w, h, head + `<div class="sh-body" style="overflow:hidden;height:${h - 64}px">${body}</div>`, 'sheet');
  if (st.overlay === 'reset') {
    const title = 'Reset puzzle progress?', msg = 'Forget every attempt? Solved, mistakes and in-progress sessions are cleared on every device.';
    const act = [{ label: 'Reset Progress', role: 'destructive' }];
    // anchored to the Reset row inside the sheet (F15), or an action sheet on compact
    if (g.compact) html += dim(cfg) + actionSheet(x, w, cfg.h - cfg.bottom - 4, title, msg, act);
    else html += popover(x + 180, y + 64 + 300, 'below', title, msg, act);
  }
  if (st.toast) html += abs(x, y + h - 80, w, 50, banner('toast', st.toast), '', 'display:flex;justify-content:center;z-index:48');
  if (st.errBanner) html += abs(x, y + h - 80, w, 50, `<span class="banner error" style="height:auto;padding:8px 8px 8px 14px">${icon('warn', 15)}Couldn't reset progress. Try again.<span class="tb" style="width:30px;height:30px;margin-left:6px">${icon('xmark', 13)}</span></span>`, '', 'display:flex;justify-content:center;z-index:48');
  return html;
}

function home(st, g0, cfg, fs) {
  let g = g0;
  const games = st.scr === 'games';
  let html = '';
  const items = [{ icon: 'person', label: 'Account', cls: 'avatar-tb' }, { icon: 'plus', label: games ? 'New Collection' : 'Import Puzzles', disabled: st.offline && !games }];
  if (st._adaptable) g = { ...g, cols: [{ x: 0, w: 200, kind: 'tabs' }, { x: 201, w: 300, kind: 'sidebar' }, { x: 502, w: 365, kind: 'detail' }] };
  const split = g.split;
  if (split && !st.empty) items.push({ icon: 'ellipsis', label: 'Collection actions' });
  // tab bar: bottom of the side bar (O, SV, IL, FB), bottom (IP, FT), top (iPad)
  const tabs = `<span class="tabbar-i${games ? '' : ' on'}">${icon('puzzle', 22)}</span><span class="tabbar-i${games ? ' on' : ''}">${icon('board', 22)}</span>`;
  const tabsH = games ? `<span class="tabbar-i">${icon('puzzle', 22)}<small>Puzzles</small></span><span class="tabbar-i on">${icon('board', 22)}<small>Games</small></span>` : `<span class="tabbar-i on">${icon('puzzle', 22)}<small>Puzzles</small></span><span class="tabbar-i">${icon('board', 22)}<small>Games</small></span>`;
  if (st._adaptable) {
    html += sideBar(cfg, items, []);
    html += abs(0, 0, 200, cfg.h, `<div style="padding:60px 12px 0"><div class="ttl" style="padding:0 8px 10px">Motif</div><div class="lrow sel" style="border-radius:10px">${icon('puzzle', 20)}<span>Puzzles</span></div><div class="lrow" style="border-radius:10px">${icon('board', 20)}<span>Games</span></div></div>`, '', 'background:var(--bg2)');
    g = { ...g, cols: g.cols.slice(1) };
  } else if (g.bars === 'side') {
    html += sideBar(cfg, items, []);
    const sx = cfg.side.edge === 'R' ? cfg.w - cfg.side.w : 0;
    html += abs(sx + (cfg.side.w - 52) / 2, cfg.h - cfg.bottom - 104, 52, 104, tabs, 'glass tabbar v');
  } else {
    html += statusBar(cfg);
    const ty = g.k === 'PD' ? 26 : cfg.h - cfg.bottom - 58;
    html += abs((cfg.w - 220) / 2, ty, 220, 56, tabsH, 'glass tabbar h');
    if (g.overlay) {
      // decision 16: detail only, with the system sidebar button; Account and + live in the sidebar column
      html += abs(12, g.top, 44, 44, icon('sidebarLeft', 21), 'tb');
      if (!st.empty) html += abs(cfg.w - 12 - 44, g.top, 44, 44, icon('ellipsis', 21), 'tb');
      if (!st.empty) html += detail(st, g.cols[0], g.top + 56);
      if (st.empty || st._sidebar) html += overlaySidebar(g, cfg, games, { empty: st.empty, offline: st.offline, waiting: st.waiting });
      else if (st.offline) html += abs(20, g.top + 56, cfg.w - 40, 30, banner('offline', st.waiting ? 'Offline · 2 waiting' : 'Offline'), '', 'display:flex;justify-content:flex-end');
      if (st.banner === 'server') html += transient(g, cfg, 'error', 'Couldn’t reach the server. Changes stay on this device until it answers.');
      if (st.banner === 'dismiss') html += transient(g, cfg, 'dismiss', 'Couldn’t rename the collection. Try again.');
      if (st.banner === 'toast') html += transient(g, cfg, 'toast', 'Collection renamed.');
      return html;
    }
    // toolbar items at the top of the sidebar column
    const c0 = g.cols[0];
    html += abs(c0.x + c0.w - 12 - 44, g.top + (g.k === 'PD' ? 30 : 0), 44, 44, `<span class="avatar">S</span>`, 'tb');
    html += abs(c0.x + c0.w - 12 - 94, g.top + (g.k === 'PD' ? 30 : 0), 44, 44, icon('plus', 21), 'tb');
    if (split && !st.empty) html += abs(cfg.w - 12 - 44, g.top + (g.k === 'PD' ? 30 : 0), 44, 44, icon('ellipsis', 21), 'tb');
  }
  const c0 = g.cols[0];
  const ty = g.bars === 'side' ? 14 : g.top + (g.k === 'PD' ? 80 : 50);
  // large title, with persistent status (offline pill) trailing it
  const sub = games ? '33 games in 3 collections' : st.empty ? '' : '26 puzzles in 3 collections';
  html += abs(c0.x + 20, ty, c0.w - 40, 60, `<div class="ttl" style="font-size:${34 * Math.min(fs, 1.3)}px;line-height:${41 * Math.min(fs, 1.3)}px">${games ? 'Games' : 'Puzzles'}</div><div class="sub">${sub}</div>`);
  if (st.offline) html += abs(c0.x + 20, ty + 4, c0.w - 40, 30, banner('offline', st.waiting ? 'Offline · 2 waiting' : 'Offline'), '', 'display:flex;justify-content:flex-end');
  const ly = ty + 72;
  const lst = { ...st, _split: split };
  const list = games ? gamesList(lst) : puzzlesList(lst, c0.w);
  if (split) html += abs(c0.x + c0.w, 0, 1, cfg.h, '', '', 'background:var(--sep)');
  if (list) html += abs(c0.x + 16, ly, c0.w - 32, cfg.h - ly - cfg.bottom, list, `listwrap${fs > 1 ? ' ax' : ''}`, `overflow:hidden;font-size:${17 * fs}px`);
  else if (!split) html += abs(c0.x, ly + 60, c0.w, 300, cuv(games ? 'board' : 'puzzle', games ? 'No Games Yet' : 'No Puzzles Yet', games ? 'Create a collection, then import PGN or play moves on the board.' : 'Import puzzles from text or a file to start solving.', pbtn(games ? 'New Collection' : 'Import Puzzles', { prom: true, dis: st.offline && !games }) + (st.offline && !games ? '<span style="font-size:13px">Importing needs a connection.</span>' : '')));
  if (split) html += detail(st, g.cols[1], g.bars === 'side' ? 22 : g.top + 56);
  html += homeOverlay(st, g, cfg, ly);
  if (st.banner === 'server') html += transient(g, cfg, 'error', 'Couldn’t reach the server. Changes stay on this device until it answers.');
  if (st.banner === 'dismiss') html += transient(g, cfg, 'dismiss', 'Couldn’t rename the collection. Try again.');
  if (st.banner === 'toast') html += transient(g, cfg, 'toast', 'Collection renamed.');
  return html;
}

// Transient banners and toasts (kit.transientBanner): bottom of the content, clear of the side bar and tab bar
function transient(g, cfg, kind, text) {
  const y = g.bars === 'side' ? cfg.h - cfg.bottom - 8 : cfg.h - cfg.bottom - 70;
  return transientBanner(g.contentX0 + 12, g.contentX1 - g.contentX0 - 24, y, kind, text);
}

function homeOverlay(st, g, cfg, ly) {
  const o = st.overlay; if (!o) return '';
  const games = st.scr === 'games';
  const c0 = g.cols[0];
  const rowY = ly + (games ? 30 : 30 + 3 * 52 + 40) + 26;
  let html = '';
  if (o === 'ctx') {
    html += abs(0, 0, cfg.w, cfg.h, '', 'dimmer', 'z-index:44;-webkit-backdrop-filter:blur(3px);backdrop-filter:blur(3px)');
    html += menu(c0.x + 40, rowY + 36, 240, [[{ label: 'Rename…', icon: 'pencil', disabled: st.offline }], [{ label: 'Delete', icon: 'trash', role: 'destructive' }]]).html;
  }
  const cx = g.k === 'FB' ? 227 : g.contentX0 + (g.contentX1 - g.contentX0) / 2, cy = cfg.h / 2 - 60;
  if (o === 'rename' || o === 'newcol') {
    html += dim(cfg);
    const title = o === 'rename' ? 'Rename the collection' : 'New Collection';
    const msg = o === 'newcol' ? '<div class="al-msg" style="height:auto">Games can be imported as PGN or played in on the board.</div>' : '';
    const val = o === 'rename' ? (games ? 'Club games' : 'Back-rank mates') : '';
    html += abs(cx - 135, cy - 80, 270, null, `<div class="al-title">${title}</div>${msg}<div class="field" style="margin:12px;height:40px;background:var(--bg)">${val || '<span style="color:var(--label3)">Name</span>'}<span class="caret"></span></div><div class="al-row"><div class="al-btn">Cancel</div><div class="al-btn primary">${o === 'rename' ? 'Save' : 'Create'}</div></div>`, 'glass alert');
    const kbH = g.compact ? 313 : 289;
    if (g.compact) html += abs(0, cfg.h - kbH, cfg.w, kbH, '<div style="padding:14px;color:var(--label2);font-size:13px;text-align:center">Keyboard</div>', 'kbd');
    else { const kl = '<div style="padding:14px;color:var(--label2);font-size:13px;text-align:center">Split keyboard</div>'; html += abs(0, cfg.h - kbH, 360, kbH, kl, 'kbd') + abs(cfg.w - 360, cfg.h - kbH, 360, kbH, kl, 'kbd'); }
  }
  if (o === 'delete') {
    const title = games ? 'Delete this collection and its games?' : 'Delete this collection and its puzzles?';
    const act = [{ label: 'Delete Collection', role: 'destructive' }];
    if (g.compact) html += dim(cfg) + actionSheet(g.contentX0 + 8, g.contentX1 - g.contentX0 - 16, cfg.h - cfg.bottom - 4, title, null, act);
    else html += popover(c0.x + 200, rowY + 26, 'below', title, null, act); // anchored to the row that asked (F15)
  }
  return html;
}

// ---------- Page ----------

function renderCanvas(prefixes) {
  let out = '';
  STATES.filter((s) => prefixes.some((p) => s.id.startsWith(p))).forEach((s) => {
    out += `<div class="state-row"><div class="state-label"><b>${s.id}</b>${s.t}</div>`;
    COLS.forEach((col) => {
      const p = cellPlan(s.id, col);
      if (p.drawn) {
        if (col === 'SV') { out += compose(s.id, 'SV', { fid: `${s.id}·SV` + (s.id === 'S04a' ? ' (left)' : '') }); if (s.id === 'S04a') out += compose(s.id, 'SVR', { geomKey: 'SVR', fid: 'S04a·SV (right)' }); }
        else out += compose(s.id, col);
        if (col === 'IP' && (s.id === 'S04a' || s.id === 'S11a')) out += compose(s.id, 'IP', { fid: `${s.id}·IP (sidebar shown)`, caption: 'After tapping the sidebar button: the home list slides over the collection', st: { _sidebar: true } });
        if (col === 'IL' && s.id === 'S04a') out += compose('S04a', 'IL', { fid: 'S04a·IL (.sidebarAdaptable)', caption: 'Comparison only (decision 4): tab sidebar instead of the tab bar', st: { _adaptable: true }, chips: [{ text: 'tab sidebar adds a third column and squeezes the detail: not chosen', kind: 'exc' }] });
      } else out += `<div class="eqcell"><b>${s.id}·${col}</b>= ${p.eq}${p.why ? `<br><i>${p.why}</i>` : ''}</div>`;
    });
    out += '</div>';
  });
  return out;
}

function renderVariants() {
  const prim = ['S01b', 'S02a', 'S03a', 'S04a', 'S11a'];
  let out = '<div class="state-row"><div class="state-label"><b>AX5</b>Dynamic Type AX5</div>';
  prim.forEach((p) => { out += compose(p, 'O', { ax5: true, fid: `${p}·O·AX5`, caption: 'AX5' }) + compose(p, 'IL', { ax5: true, fid: `${p}·IL·AX5`, caption: 'AX5' }); });
  out += '</div><div class="state-row"><div class="state-label"><b>RT</b>Reduce Transparency</div>';
  prim.forEach((p) => { out += compose(p, 'O', { rt: true, fid: `${p}·O·RT`, caption: 'Reduce Transparency' }) + compose(p, 'IL', { rt: true, fid: `${p}·IL·RT`, caption: 'Reduce Transparency' }); });
  return out + '</div>';
}

function renderCoverage() {
  let rows = '', drawn = 0, eq = 0;
  STATES.forEach((s) => {
    rows += `<tr><th style="text-align:left">${s.id} <span style="font-weight:400">${s.t}</span></th>`;
    COLS.forEach((col) => { const p = cellPlan(s.id, col); if (p.drawn) { drawn++; rows += `<td class="drawn"><a href="#${s.id}·${col}">●</a></td>`; } else { eq++; rows += `<td class="eq">= ${p.eq}</td>`; } });
    rows += '</tr>';
  });
  const hosts = ['S15', 'S09'].map((h) => ['a', 'b', 'c', 'd', 'e'].map((x) => `<tr><th style="text-align:left">S17${x}-${h}</th><td colspan="8" class="eq">on the ${h === 'S15' ? 'Analysis' : 'Session and detail'} canvas (O, IL drawn; other columns equal a drawn frame there)</td></tr>`).join('')).join('');
  return `<p>${STATES.length} states × ${COLS.length} configurations = ${STATES.length * COLS.length} cells: <b>${drawn} drawn</b>, ${eq} equal to a drawn frame, 0 blank. Plus 20 system-variant frames, S04a·IP and S11a·IP with the sidebar shown, S04a on the right Split View half and the .sidebarAdaptable comparison. S17 on the S09 and S15 hosts is drawn on those canvases.</p><table class="cov"><tr><th></th>${COLS.map((c) => `<th>${c}</th>`).join('')}</tr>${rows}${hosts}</table>`;
}
