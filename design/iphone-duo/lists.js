// Lists canvas (S06 Collection, S07 Puzzle list, S12 Game collection). Plan §5, §7 (Lists).
// Regular width: these screens are the detail column of the tab's NavigationSplitView
// (decision 12); the sidebar keeps the home list with the collection selected.
// Compact: today's stack. Swipe actions, context menus and edit mode stay unchanged.

const COLS = ['O', 'IL', 'IP', 'SV', 'FB', 'FT', 'PP', 'PD'];

const STATES = [
  { id: 'S06a', t: 'Stats card', scr: 'coll' },
  { id: 'S06b', t: 'Session in progress (Resume, Discard)', scr: 'coll', session: true },
  { id: 'S06c', t: 'Overflow menu', scr: 'coll', overlay: 'menu' },
  { id: 'S06d', t: 'Empty', scr: 'coll', empty: true },
  { id: 'S06e', t: 'Rename alert', scr: 'coll', overlay: 'rename' },
  { id: 'S06f', t: 'Delete confirmation', scr: 'coll', overlay: 'delete' },
  { id: 'S06g', t: 'Offline', scr: 'coll', offline: true },
  { id: 'S07a', t: 'Default', scr: 'plist' },
  { id: 'S07b', t: 'Searching (scopes shown, F23)', scr: 'plist', search: 'active' },
  { id: 'S07c', t: 'Scope applied with a query', scr: 'plist', search: 'query', scope: 'To review' },
  { id: 'S07d', t: 'Empty scope', scr: 'plist', search: 'active', scope: 'Flagged', emptyScope: true },
  { id: 'S07e', t: 'No search results', scr: 'plist', search: 'nomatch' },
  { id: 'S07f', t: 'No puzzles', scr: 'plist', empty: true },
  { id: 'S07g', t: 'Swipe actions', scr: 'plist', swipe: true },
  { id: 'S07h', t: 'Delete confirmation', scr: 'plist', overlay: 'delete' },
  { id: 'S07i', t: 'Offline', scr: 'plist', offline: true },
  { id: 'S12a', t: 'Browse', scr: 'games' },
  { id: 'S12b', t: 'Search, no match', scr: 'games', search: 'nomatch' },
  { id: 'S12c', t: '+ menu (Add Games)', scr: 'games', overlay: 'add' },
  { id: 'S12d', t: 'Overflow menu', scr: 'games', overlay: 'menu' },
  { id: 'S12e', t: 'Edit mode, none selected', scr: 'games', edit: 0 },
  { id: 'S12f', t: 'Edit mode with selection + bulk bar', scr: 'games', edit: 2 },
  { id: 'S12g', t: 'All selected', scr: 'games', edit: 8 },
  { id: 'S12h', t: 'Reorder (handles)', scr: 'games', edit: 0, reorder: true },
  { id: 'S12i', t: 'Move/copy destination sheet', scr: 'games', edit: 2, overlay: 'dest' },
  { id: 'S12j', t: 'Rename alert', scr: 'games', overlay: 'rename' },
  { id: 'S12k', t: 'Delete collection confirmation', scr: 'games', overlay: 'delete' },
  { id: 'S12l', t: 'Delete selected confirmation', scr: 'games', edit: 2, overlay: 'delsel' },
  { id: 'S12m', t: 'Empty', scr: 'games', empty: true },
  { id: 'S12n', t: 'Empty offline', scr: 'games', empty: true, offline: true },
  { id: 'S12o', t: 'Offline', scr: 'games', offline: true },
  { id: 'S12p', t: 'Edit mode offline', scr: 'games', edit: 2, offline: true },
  { id: 'S12q', t: 'Share sheet', scr: 'games', edit: 2, overlay: 'share' },
];
const S = Object.fromEntries(STATES.map((s) => [s.id, s]));

const DRAW = {
  IP: ['S06a', 'S07a', 'S07b', 'S12a', 'S12f', 'S12i'],
  SV: ['S06a', 'S07a', 'S12a', 'S12f'],
  FB: ['S06a', 'S07a', 'S07b', 'S12a', 'S12f', 'S12i', 'S12k', 'S12q'],
  PD: ['S06a', 'S07a', 'S12a'],
};
const OVERLAY = new Set(STATES.filter((s) => s.overlay).map((s) => s.id));
const PRIM = { coll: 'S06a', plist: 'S07a', games: 'S12a' };

function cellPlan(id, col) {
  if (col === 'O' || col === 'IL') return { drawn: true };
  if ((DRAW[col] || []).includes(id)) return { drawn: true };
  const st = S[id], prim = st.edit != null ? 'S12f' : PRIM[st.scr];
  switch (col) {
    case 'IP': return OVERLAY.has(id) ? { eq: `${id}·IL`, why: 'overlay, regular (§5.5)' } : { eq: `${prim}·IP + detail of ${id}·IL` };
    case 'SV': return { eq: `${id}·O`, why: 'compact width (device-checked)' };
    case 'FB': return OVERLAY.has(id) ? { eq: `${id}·IL, on the right page` } : { eq: `${prim}·FB + detail of ${id}·IL` };
    case 'FT': return { eq: `${id}·IP`, why: 'lists are scrolling content; overlays sit below the fold' };
    case 'PP': return { eq: `${id}·IL`, why: 'decision 9' };
    case 'PD': return { eq: `${id}·IL`, why: 'iPad = regular layouts (D11)' };
  }
}

// ---------- Data ----------

const PUZZLES = [
  ['#1', 'Back rank · Mate in 1 · 800', 'Solved', true], ['#2', 'Back rank · Trade · 950', 'To review'], ['#3', 'Back rank · 1100', 'New'],
  ['#4', 'Back rank · Deflection · 1250', 'New', false, true], ['#5', 'Back rank · Mate in 2 · 1300', 'Solved'], ['#6', 'Back rank · Decoy · 1400', 'New'],
  ['#7', 'Back rank · Mate in 2 · 1450', 'To review'], ['#8', 'Back rank · Clearance · 1500', 'New'],
];
const GAMES = [
  ['Me – Club friend', 'Club championship · Round 4 · 2026.10.12', '1–0'], ['New game – ?', '', ''], ['Endgame study – ?', '', ''],
  ['Alpha – Beta', 'Club night · Round 1', '½–½'], ['Me – Engine', 'Club night · Round 2', '0–1'], ['Club friend – Me', 'Club night · Round 3', '1–0'],
  ['Carlsen – Nakamura', 'Club night · Round 4', ''], ['Me – Coach', 'Club night · Round 5', '½–½'],
];

// ---------- Blocks ----------

function search(w, st) {
  const active = !!st.search;
  const q = st.search === 'query' ? 'back' : st.search === 'nomatch' ? 'zzz' : '';
  const field = `<div class="search${active ? ' on' : ''}" style="width:${active ? w - 52 : w}px">${icon('search', 17)}${q ? `<span>${q}</span>` : `<span style="color:var(--label3)">${st.scr === 'games' ? 'Players, event, opening' : 'Number or motif'}</span>`}${active ? '<span class="caret" style="display:inline-block;width:2px;height:20px;background:var(--accent)"></span>' : ''}</div>`;
  const cancel = active ? `<span class="tb" style="width:44px;height:44px;flex:none">${icon('xmark', 17)}</span>` : '';
  let html = `<div style="display:flex;gap:8px;align-items:center">${field}${cancel}</div>`;
  let h = 44;
  // F23: scopes show as soon as search is presented, with or without a query (.searchScopes activation: .onSearchPresentation)
  if (st.scr === 'plist' && active) {
    const scopes = ['All', 'New', 'To review', 'Solved', 'Flagged'];
    const sel = st.scope || 'All';
    html += `<div class="seg" style="margin-top:8px">${scopes.map((x) => `<span class="${x === sel ? 'on' : ''}">${x}</span>`).join('')}</div>`;
    h += 44;
  }
  return { html, h };
}

function thumb() {
  return `<span class="thumb">${board(36, { fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1' }).replace(/<span class="coord[^<]*<\/span>/g, '')}</span>`;
}

function puzzleRows(st) {
  let list = PUZZLES;
  if (st.search === 'query') list = PUZZLES.filter((p) => p[2] === 'To review');
  return list.map(([n, sub, status, _x, flag], i) => {
    const color = status === 'Solved' ? 'var(--accent)' : status === 'To review' ? '#c93400' : 'var(--label2)';
    const trail = `${flag ? `<span style="color:#ff9500">${icon('flagFill', 15)}</span>` : ''}<span class="status" style="color:${color}">${status}</span>`;
    const r = row({ lead: thumb(), title: `<span style="font-variant-numeric:tabular-nums">${n}</span>`, sub, trail, chev: true, cls: (st.swipe && i === 1 ? 'swiped2' : '') + (st.overlay === 'delete' && i === 1 ? ' lifted' : '') });
    if (st.swipe && i === 1) return `<div class="swipewrap">${r}<span class="swipe-btn gray" style="background:#ff9500">${icon('flag', 20)}<span>Flag</span></span><span class="swipe-btn red">${icon('trash', 20)}<span>Delete</span></span></div>`;
    return r;
  });
}

function gameRows(st) {
  const editing = st.edit != null;
  return GAMES.map(([t, sub, res], i) => {
    const sel = editing && (st.edit === 8 || i < st.edit);
    const lead = editing ? `<span class="selcirc${sel ? ' on' : ''}">${sel ? icon('check', 13, 3) : ''}</span>` : '';
    const trail = (res ? `<span class="resbadge">${res}</span>` : '') + (editing ? '<span class="handle">≡</span>' : '');
    return row({ lead, title: t, sub, trail, chev: !editing, cls: (sel ? 'picked' : '') + (st.reorder && i === 3 ? ' lifted' : '') });
  });
}

function collContent(st, w) {
  let h = '';
  if (st.session) h += section('', [`<div class="lrow" style="flex-direction:column;align-items:stretch;gap:10px;padding:14px 16px"><span style="display:flex;justify-content:space-between"><b>Session in Progress</b><span class="lr-v">2 left</span></span><span style="display:flex;gap:10px"><span class="btn prom" style="height:44px;flex:1">${icon('skip', 15)}Resume</span><span class="btn" style="height:44px;color:var(--red);background:var(--fill3)">Discard Session</span></span></div>`]);
  const tileC = (n, l, c) => `<span style="flex:1;display:flex;flex-direction:column"><b style="font-size:24px;color:${c};font-variant-numeric:tabular-nums">${n}</b><span class="lr-s">${l}</span></span>`;
  h += section('', [`<div class="lrow" style="flex-direction:column;align-items:stretch;gap:12px;padding:14px 16px"><span style="display:flex">${tileC(1, 'Solved', 'var(--accent)')}${tileC(1, 'To review', '#c93400')}${tileC(1, 'New', 'var(--label)')}</span><span class="progress"><span style="width:33%"></span></span></div>`]);
  h += section('Solve', [row({ lead: `<span style="color:var(--accent)">${icon('lines', 20)}</span>`, title: '<span style="color:var(--accent)">Solve in Order</span>' }), row({ lead: `<span style="color:var(--accent)">${icon('sparkle', 20)}</span>`, title: '<span style="color:var(--accent)">Solve Shuffled</span>' })]);
  h += section('', [row({ lead: `<span style="color:var(--accent)">${icon('board', 20)}</span>`, title: 'All Puzzles', trail: '<span class="lr-v">3</span>', chev: true })]);
  return h;
}

// ---------- Composer ----------

function toolbarFor(st, split) {
  const top = [];
  if (st.edit != null) {
    // F30: Select All becomes a titled toolbar item with a symbol; Done is the prominent action
    top.push({ icon: 'check', label: 'Done', on: true });
    top.push({ icon: st.edit === 8 ? 'xmark' : 'lines', label: st.edit === 8 ? 'Deselect All' : 'Select All' });
    const off = st.offline, none = st.edit === 0;
    const bottom = [{ icon: 'folder', label: 'Move', disabled: none || off }, { icon: 'doc', label: 'Copy', disabled: none || off }, { icon: 'share', label: 'Export', disabled: none }, { icon: 'trash', label: 'Delete', disabled: none || off, cls: 'redtb' }];
    return { top, bottom };
  }
  if (split) { top.push({ icon: 'person', label: 'Account', cls: 'avatar-tb' }); }
  if (!split || st.scr === 'plist') top.unshift({ icon: 'chevL', label: 'Back' });
  if (st.scr === 'games') top.push({ icon: 'plus', label: 'Add Games' });
  if (st.scr !== 'plist') top.push({ icon: 'ellipsis', label: 'More' });
  return { top, bottom: [] };
}

function compose(id, k, opts = {}) {
  const st = { ...S[id], ...(opts.st || {}) };
  const gk = opts.geomKey || (k === 'SV' ? 'SVL' : k);
  const cfg = CFG[gk];
  const g = shellGeom(gk);
  const split = g.cols.length > 1;
  const fs = opts.ax5 ? 1.9 : 1;
  const tb = toolbarFor(st, split);
  const editing = st.edit != null;
  let html = '';
  const games = st.scr === 'games';

  // bars + tab bar (hidden in edit mode)
  const tabsV = `<span class="tabbar-i${games ? '' : ' on'}">${icon('puzzle', 22)}</span><span class="tabbar-i${games ? ' on' : ''}">${icon('board', 22)}</span>`;
  const tabsH = `<span class="tabbar-i${games ? '' : ' on'}">${icon('puzzle', 22)}<small>Puzzles</small></span><span class="tabbar-i${games ? ' on' : ''}">${icon('board', 22)}<small>Games</small></span>`;
  if (g.bars === 'side') {
    html += sideBar(cfg, tb.top, editing ? [] : []);
    const sx = cfg.side.edge === 'R' ? cfg.w - cfg.side.w : 0;
    if (editing) {
      // bulk items: .bottomBar group → bottom of the side bar
      let by = cfg.h - cfg.bottom - 44;
      [...tb.bottom].reverse().forEach((it) => { html += abs(sx + (cfg.side.w - 44) / 2, by, 44, 44, icon(it.icon, 20), `tb ${it.disabled ? 'dis' : ''} ${it.cls || ''}`); by -= 52; });
    } else html += abs(sx + (cfg.side.w - 52) / 2, cfg.h - cfg.bottom - 104, 52, 104, tabsV, 'glass tabbar v');
  } else {
    html += statusBar(cfg);
    const d = g.cols[g.cols.length - 1], c0 = g.cols[0];
    const ty = g.top + (gk === 'PD' ? 30 : 0);
    // sidebar column items
    html += abs(c0.x + c0.w - 56, ty, 44, 44, '<span class="avatar">S</span>', 'tb');
    // detail items
    let x = d.x + d.w - 56;
    tb.top.filter((i) => !(i.cls || '').includes('avatar') && i.icon !== 'chevL').reverse().forEach((it) => { html += abs(x, ty, 44, 44, icon(it.icon, 20), `tb ${it.on ? 'on' : ''}`); x -= 50; });
    if (tb.top.some((i) => i.icon === 'chevL')) html += abs(d.x + 12, ty, 44, 44, icon('chevL', 20), 'tb');
    if (editing) html += abs(d.x, cfg.h - cfg.bottom - 56, d.w, 50, `<span class="glass bulkbar">${tb.bottom.map((it) => `<span class="${it.disabled ? 'dis' : ''} ${it.cls || ''}">${icon(it.icon, 18)}${d.w >= 440 ? it.label : ''}</span>`).join('')}</span>`, '', 'display:flex;justify-content:center;z-index:22');
    else html += abs((cfg.w - 220) / 2, gk === 'PD' ? 26 : cfg.h - cfg.bottom - 58, 220, 56, tabsH, 'glass tabbar h');
  }

  // sidebar column (regular): home list with the collection selected
  if (split) {
    const c0 = g.cols[0];
    const ty = g.bars === 'side' ? 14 : g.top + (gk === 'PD' ? 80 : 50);
    html += abs(c0.x + 20, ty, c0.w - 40, 60, `<div class="ttl" style="font-size:34px;line-height:41px">${games ? 'Games' : 'Puzzles'}</div><div class="sub">${games ? '33 games in 3 collections' : '26 puzzles in 3 collections'}</div>`);
    html += abs(c0.x + 16, ty + 72, c0.w - 32, cfg.h - ty - 72 - cfg.bottom, games ? gamesList({ _split: true }) : puzzlesList({ _split: true }), 'listwrap', 'overflow:hidden');
    html += abs(c0.x + c0.w, 0, 1, cfg.h, '', '', 'background:var(--sep)');
  }

  // detail / single column
  const d = g.cols[g.cols.length - 1];
  const x = d.x + 16, w = Math.min(d.w - 32, 672);
  let y = g.bars === 'side' ? 14 : g.top + (gk === 'PD' ? 80 : 50);
  const title = st.scr === 'coll' ? 'Back-rank mates' : st.scr === 'plist' ? 'All Puzzles' : editing ? (st.edit === 0 ? 'Select Games' : `${st.edit} Selected`) : 'Club games';
  const sub = st.scr === 'coll' ? '' : st.scr === 'plist' ? 'Back-rank mates' : editing ? '' : '24 games';
  const large = st.scr === 'coll' && !split;
  const searching = st.search && (st.search === 'active' || st.search === 'nomatch' || st.search === 'query');
  if (!(searching && st.scr === 'plist')) {
    html += abs(x + 4, y, w - (st.offline ? 100 : 0), 50, `<div class="ttl" style="font-size:${(large ? 34 : 22) * Math.min(fs, 1.3)}px;line-height:${(large ? 41 : 28) * Math.min(fs, 1.3)}px">${title}</div>${sub ? `<div class="sub">${sub}</div>` : ''}`);
    if (st.offline) html += abs(x, y + 2, w, 30, banner('offline', 'Offline'), '', 'display:flex;justify-content:flex-end');
    y += large ? 62 : 52;
  }
  if (st.scr !== 'coll' && !(st.empty && st.scr === 'plist')) {
    if (!st.empty) { const sr = search(w, st); html += abs(x, y, w, sr.h, sr.html); y += sr.h + 10; }
  }
  const bottom = cfg.h - cfg.bottom - (g.bars === 'nav' ? 64 : 0) - (editing && g.bars === 'nav' ? 0 : 0);
  let body = '';
  if (st.empty) {
    const games2 = st.scr === 'games';
    body = cuv(games2 ? 'board' : 'puzzle', games2 ? 'No Games' : 'No Puzzles', games2 ? 'Import PGN or start a new game on the board.' : 'Import puzzles into this collection to start solving.', games2 ? pbtn('Import PGN…', { prom: true, dis: st.offline }) + pbtn('New Game on Board…') : pbtn('Import Puzzles', { prom: true, dis: st.offline }));
    html += abs(x, y + 80, w, 300, body);
  } else if (st.search === 'nomatch') {
    html += abs(x, y + 60, w, 200, cuv('search', `No Results for “zzz”`, 'Check the spelling or try a new search.'));
  } else if (st.emptyScope) {
    html += abs(x, y + 60, w, 200, cuv('flag', 'No Flagged Puzzles', 'Flag a puzzle from its detail or during a session.'));
  } else {
    if (st.scr === 'coll') body = collContent(st, w);
    else if (st.scr === 'plist') body = section('', puzzleRows(st));
    else body = section('', gameRows(st));
    html += abs(x, y, w, bottom - y, body, `listwrap${fs > 1 ? ' ax' : ''}`, `overflow:hidden;font-size:${17 * fs}px`);
  }
  // keyboard for active search
  if (st.search === 'active' || st.search === 'query') html += keyboard(g, cfg);
  html += overlays(st, g, cfg, d, x, w);
  const chips = [{ text: cfg.size }, { text: split ? `detail column of NavigationSplitView (${Math.round(d.w)} pt)` : 'NavigationStack (split collapsed)', kind: 'ct' }];
  if (editing) chips.push({ text: g.bars === 'side' ? 'bulk bar: .bottomBar → bottom of the side bar; tab bar hidden' : (d.w >= 440 ? 'bulk bar: .bottomBar, titled items' : 'bulk bar: .bottomBar, symbols (column too narrow for titles)'), kind: 'ct' });
  if (gk === 'FB') chips.push({ text: 'sidebar on the left page, detail on the right', kind: 'fix' });
  if (w < d.w - 32) chips.push({ text: 'readable width 672 pt', kind: 'fix' });
  (opts.chips || []).forEach((c) => chips.push(c));
  return frame(opts.fid || `${id}·${k}`, gk, html, chips, { caption: opts.caption || st.t, cls: (opts.rt ? 'rt ' : '') + (opts.ax5 ? 'ax5' : '') });
}

function keyboard(g, cfg) {
  const kl = (t) => `<div style="padding:14px;color:var(--label2);font-size:13px;text-align:center">${t}</div>`;
  if (g.compact) return abs(0, cfg.h - 313, cfg.w, 313, kl('Keyboard 313 pt'), 'kbd');
  return abs(0, cfg.h - 289, 360, 289, kl('Split keyboard 289 pt'), 'kbd') + abs(cfg.w - 360, cfg.h - 289, 360, 289, kl('Split keyboard 289 pt'), 'kbd');
}

function overlays(st, g, cfg, d, x, w) {
  const o = st.overlay; if (!o) return '';
  let html = '';
  const sideX = cfg.side ? (cfg.side.edge === 'R' ? cfg.w - cfg.side.w : cfg.side.w) : null;
  const tb = toolbarFor(st, g.cols.length > 1);
  const itemY = (icon) => 186 + 52 * tb.top.findIndex((i) => i.icon === icon);
  const menuAt = (iconName, w2) => g.bars === 'side' ? { x: (cfg.side.edge === 'R' ? sideX - w2 - 8 : sideX + 8), y: itemY(iconName) - 6 } : { x: d.x + d.w - 12 - w2, y: g.top + 50 };
  if (o === 'menu') {
    // F16: custom actions in ToolbarOverflowMenu
    const secs = st.scr === 'coll'
      ? [[{ label: 'Rename…', icon: 'pencil', disabled: st.offline }, { label: 'Import Into Collection…', icon: 'save', disabled: st.offline }], [{ label: 'Delete Collection', icon: 'trash', role: 'destructive', disabled: st.offline }]]
      : [[{ label: 'Select Games', icon: 'check' }, { label: 'Export as PGN', icon: 'share' }], [{ label: 'Rename…', icon: 'pencil' }], [{ label: 'Delete Collection', icon: 'trash', role: 'destructive' }]];
    const p = menuAt('ellipsis', 260);
    html += menu(p.x, p.y, 260, secs).html;
  }
  if (o === 'add') { const p = menuAt('plus', 250); html += menu(p.x, p.y, 250, [[{ label: 'Import PGN…', icon: 'doc' }, { label: 'New Game on Board…', icon: 'board' }]]).html; }
  if (o === 'rename') {
    const cx = g.k === 'FB' ? 681 : d.x + d.w / 2;
    html += dim(cfg) + abs(cx - 135, cfg.h / 2 - 180, 270, null, `<div class="al-title">Rename the collection</div><div class="field" style="margin:12px;height:40px;background:var(--bg)">${st.scr === 'games' ? 'Club games' : 'Back-rank mates'}<span class="caret"></span></div><div class="al-row"><div class="al-btn">Cancel</div><div class="al-btn primary">Save</div></div>`, 'glass alert');
    html += keyboard(g, cfg);
  }
  if (o === 'delete' || o === 'delsel') {
    const title = o === 'delsel' ? 'Delete the selected games?' : st.scr === 'plist' ? 'Delete this puzzle from the library?' : st.scr === 'games' ? 'Delete this collection and its games?' : 'Delete this collection and its puzzles?';
    const act = [{ label: o === 'delsel' ? 'Delete 2 Games' : st.scr === 'plist' ? 'Delete Puzzle' : 'Delete Collection', role: 'destructive' }];
    if (g.compact) html += dim(cfg) + actionSheet(d.x + 8, d.w - 16, cfg.h - cfg.bottom - 4, title, null, act);
    else if (o === 'delsel') html += g.bars === 'side' ? popover(sideX, cfg.h - cfg.bottom - 22, 'left', title, null, act) : popover(d.x + d.w / 2 + 140, cfg.h - cfg.bottom - 56, 'above', title, null, act);
    else if (st.scr === 'plist') html += popover(x + 220, 14 + 52 + 44 + 10 + 60 + 30, 'below', title, null, act);
    else html += g.bars === 'side' ? popover(sideX, itemY('ellipsis') + 22, 'left', title, null, act) : popover(d.x + d.w - 34, g.top + 44, 'below', title, null, act);
  }
  if (o === 'dest') {
    const rows = [{ label: 'Club games', value: 'Current collection' }, { label: 'Study games', value: '8 games', sel: true }, { label: 'Openings', value: '1 game' }];
    const body = `<div class="form-h">MOVE TO</div>${formRows(rows)}`;
    const h = 64 + 26 + 3 * 48 + 30;
    html += dim(cfg);
    if (g.compact) {
      const sy = cfg.h - 8 - h;
      html += sheet(8 + (cfg.side.edge === 'L' ? 84 : 0), sy, cfg.w - 16 - 76, h, 'Move 2 Games', body, { sideControls: true, grabber: true });
      const bx = cfg.side.edge === 'R' ? cfg.w - cfg.side.w + 20 : 20;
      html += abs(bx, sy + 10, 44, 44, icon('xmark', 19), 'tb', 'z-index:47') + abs(bx, sy + 62, 44, 44, icon('check', 20), 'tb on', 'z-index:47');
    } else if (g.k === 'FB') html += sheet(8, 60, 440, h, 'Move 2 Games', body);
    else html += sheet((cfg.w - (cfg.side ? cfg.side.w : 0) - 520) / 2, (cfg.h - h) / 2, 520, h, 'Move 2 Games', body);
  }
  if (o === 'share') {
    const apps = ['Messages', 'Mail', 'Files', 'Notes'].map((a) => `<span class="shapp"><span></span>${a}</span>`).join('');
    const body = `<div style="display:flex;gap:12px;align-items:center;padding:4px 4px 14px"><span class="itile" style="width:44px;height:44px;background:var(--fill2);color:var(--label)">${icon('doc', 22)}</span><span style="display:flex;flex-direction:column"><b>Club games.pgn</b><span class="lr-s">2 games · PGN</span></span></div><div style="display:flex;gap:14px">${apps}</div><div class="glist" style="margin-top:14px">${['Copy', 'Save to Files'].map((a) => `<div class="gl-row">${a}</div>`).join('')}</div>`;
    if (g.compact) { html += dim(cfg) + abs(8, cfg.h - 8 - 330, cfg.w - 16 - (cfg.side ? 76 : 0), 330, `<div style="padding:16px">${body}</div>`, 'sheet'); }
    else {
      // regular: popover anchored to the Export item (system)
      const ax = g.bars === 'side' ? sideX : d.x + d.w / 2;
      const ay = g.bars === 'side' ? cfg.h - cfg.bottom - 44 - 52 - 22 : cfg.h - cfg.bottom - 56;
      const px = g.bars === 'side' ? ax - 340 - 14 : ax - 170, py = g.bars === 'side' ? ay - 150 : ay - 330 - 14;
      html += abs(px, py, 340, 310, `<span class="pop-arrow" style="${g.bars === 'side' ? `right:-7px;top:${ay - py - 7}px` : `bottom:-7px;left:${ax - px - 7}px`}"></span><div style="padding:16px">${body}</div>`, 'glass popover');
    }
  }
  return html;
}

// ---------- Page ----------

function renderCanvas(prefix) {
  let out = '';
  STATES.filter((s) => s.id.startsWith(prefix)).forEach((s) => {
    out += `<div class="state-row"><div class="state-label"><b>${s.id}</b>${s.t}</div>`;
    COLS.forEach((col) => {
      const p = cellPlan(s.id, col);
      if (p.drawn) {
        if (col === 'SV') { out += compose(s.id, 'SV', { fid: `${s.id}·SV` + (s.id === 'S12f' ? ' (left)' : '') }); if (s.id === 'S12f') out += compose(s.id, 'SVR', { geomKey: 'SVR', fid: 'S12f·SV (right)' }); }
        else out += compose(s.id, col);
      } else out += `<div class="eqcell"><b>${s.id}·${col}</b>= ${p.eq}${p.why ? `<br><i>${p.why}</i>` : ''}</div>`;
    });
    out += '</div>';
  });
  return out;
}

function renderVariants() {
  const prim = ['S06a', 'S07a', 'S12a'];
  let out = '<div class="state-row"><div class="state-label"><b>AX5</b>Dynamic Type AX5</div>';
  prim.forEach((p) => { out += compose(p, 'O', { ax5: true, fid: `${p}·O·AX5`, caption: 'AX5' }) + compose(p, 'IL', { ax5: true, fid: `${p}·IL·AX5`, caption: 'AX5' }); });
  out += '</div><div class="state-row"><div class="state-label"><b>RT</b>Reduce Transparency</div>';
  prim.forEach((p) => { out += compose(p, 'O', { rt: true, fid: `${p}·O·RT`, caption: 'Reduce Transparency' }) + compose(p, 'IL', { rt: true, fid: `${p}·IL·RT`, caption: 'Reduce Transparency' }); });
  return out + '</div>';
}

function renderStoryboards() {
  return `<h2>Enter Split View from IL in edit mode (S12f)</h2><div class="story">`
    + compose('S12f', 'IL', { fid: '1 · open, edit mode', caption: '2 games selected; bulk items at the bottom of the side bar' })
    + '<span class="arrow">→</span>'
    + compose('S12f', 'SVR', { geomKey: 'SVR', fid: '2 · Split View, right half', caption: 'Compact: the split collapses to the game collection; selection and edit mode kept; bars on the outer (trailing) edge' })
    + '<span class="arrow">→</span>'
    + compose('S12f', 'SV', { fid: '3 · moved to the left half', caption: 'Bars follow to the leading edge; still 2 selected, focus on the list' })
    + '</div>';
}

function renderCoverage() {
  let rows = '', drawn = 0, eq = 0;
  STATES.forEach((s) => {
    rows += `<tr><th style="text-align:left">${s.id} <span style="font-weight:400">${s.t}</span></th>`;
    COLS.forEach((col) => { const p = cellPlan(s.id, col); if (p.drawn) { drawn++; rows += `<td class="drawn"><a href="#${s.id}·${col}">●</a></td>`; } else { eq++; rows += `<td class="eq">= ${p.eq}</td>`; } });
    rows += '</tr>';
  });
  return `<p>${STATES.length} states × ${COLS.length} configurations = ${STATES.length * COLS.length} cells: <b>${drawn} drawn</b>, ${eq} equal to a drawn frame, 0 blank. Plus 12 system-variant frames, 3 storyboard frames and S12f on the right Split View half.</p><table class="cov"><tr><th></th>${COLS.map((c) => `<th>${c}</th>`).join('')}</tr>${rows}</table>`;
}
