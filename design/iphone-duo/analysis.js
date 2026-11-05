// Analysis canvas (S15 Analysis view, S10 Puzzle analysis). Plan §5, §7.
// One table of states, one layout rule, one composer: every frame is generated.

// ---------- Fixture data ----------

const GAME = {
  title: 'Me – Club friend',
  sub: '1-0 · Club championship · Ruy Lopez · 2026.10.12',
  fen: 'r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4',
  hl: ['a7', 'a6'],
  eval: { frac: 0.54, label: '0.4' },
  rows: [
    { n: 1, w: 'e4', b: 'e5' }, { n: 2, w: 'Nf3', b: 'Nc6' }, { n: 3, w: 'Bb5', b: 'a6', sel: 'b' },
    { n: 4, w: 'Ba4', b: 'Nf6' }, { n: 5, w: 'O-O', b: 'Be7' }, { n: 6, w: 'Re1', b: 'b5' },
    { n: 7, w: 'Bb3', b: 'd6' }, { n: 8, w: 'c3', b: 'O-O' }, { n: 9, w: 'h3', b: 'Na5' },
    { n: 10, w: 'Bc2', b: 'c5' }, { n: 11, w: 'd4', b: 'Qc7' }, { n: 12, w: 'Nbd2', b: 'cxd4' },
    { n: 13, w: 'cxd4', b: 'Nc6' }, { n: 14, w: 'Nb3', b: 'a5' },
  ],
  vari: { after: 2, text: '3… Nf6 4. O-O Nxe4 5. d4 Nd6' },
  lines: [
    { ev: '+0.45', pv: '4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6' },
    { ev: '+0.30', pv: '4. Bxc6 dxc6 5. O-O f6 6. d4 exd4' },
    { ev: '+0.18', pv: '4. Bc4 Nf6 5. d3 Bc5 6. c3 d6' },
  ],
  alts: ['3… a6', '3… Nf6', '3… Bc5', '3… d6', '3… f5'],
  comment: 'The Morphy Defence. 4. Bxc6 gives up the bishop pair for a better pawn structure.',
};

const PUZZLE = {
  title: 'Puzzle 14',
  sub: 'Analysis · Tactics 2026 · White to move',
  fen: 'r2qk2r/ppp2ppp/2np1n2/2b1p1B1/2B1P1b1/2NP1N2/PPP2PPP/R2QK2R w KQkq - 0 7',
  hl: ['d5', 'c3'],
  rows: [{ n: 7, w: 'Nd5', b: 'Nd4', sel: 'w' }, { n: 8, w: 'Nxf6+', b: 'gxf6' }, { n: 9, w: 'Bh4', b: 'Bxf3' }, { n: 10, w: 'gxf3', b: 'Qd7' }],
};

const PROMO = {
  fen: '8/4P1k1/8/5K2/8/8/8/8 w - - 0 60', hl: ['e7', 'e8'], ghost: { sq: 'e8', piece: 'q' },
  rows: [{ n: 57, w: 'Kf5', b: 'Kh7' }, { n: 58, w: 'e6', b: 'Kg7' }, { n: 59, w: 'e7', b: 'Kf7?', sel: 'b' }],
};

// ---------- States (plan §4; S10 per §8.4) ----------

const STATES = [
  { id: 'S15a', t: 'Default, eval bar on' },
  { id: 'S15b', t: 'Evaluation hidden', noEval: true },
  { id: 'S15c', t: 'Engine lines', lines: true },
  { id: 'S15d', t: 'Engine starting', lines: true, starting: true },
  { id: 'S15e', t: 'Comment card', comment: true },
  { id: 'S15f', t: 'Alternatives (≤ 3)', alts: true },
  { id: 'S15g', t: 'Alternatives expanded', alts: true, altsOpen: true },
  { id: 'S15h', t: 'Variation in the list', vari: true },
  { id: 'S15i', t: 'No moves yet', empty: true },
  { id: 'S15j', t: 'At start (‹ disabled)', atStart: true },
  { id: 'S15k', t: 'Promotion picker', promo: true },
  { id: 'S15l', t: 'Move context menu', overlay: 'ctx' },
  { id: 'S15m', t: 'Delete-from-here confirmation', overlay: 'delmove' },
  { id: 'S15n', t: 'Game menu (overflow)', overlay: 'menu' },
  { id: 'S15o', t: 'Delete game confirmation', overlay: 'delgame' },
  { id: 'S15p', t: 'Unsaved: back alert', overlay: 'unsaved' },
  { id: 'S15q', t: 'Unsaved, offline: discard alert', overlay: 'unsavedOff', offline: true },
  { id: 'S15r', t: 'Offline', offline: true },
  { id: 'S15s', t: 'Illegal move in PGN', problem: true },
  { id: 'S15t', t: 'Unreadable PGN', unreadable: true },
  { id: 'S15u', t: 'Unreadable PGN, offline', unreadable: true, offline: true },
  { id: 'S15v', t: 'Densest: lines + comment + alternatives', lines: true, comment: true, alts: true },
  { id: 'S10a', t: 'Solution preloaded', puzzle: true },
  { id: 'S10b', t: 'Missing piece placed', puzzle: true, missing: true },
  { id: 'S10c', t: 'Overflow menu', puzzle: true, overlay: 'pmenu' },
  { id: 'S10d', t: 'Save as Game: existing collection', puzzle: true, overlay: 'save' },
  { id: 'S10e', t: 'Save as Game: new collection', puzzle: true, overlay: 'saveNew' },
  { id: 'S10f', t: 'Offline (F14 fixed)', puzzle: true, offline: true },
];
const S = Object.fromEntries(STATES.map((s) => [s.id, s]));

// ---------- Which cells are drawn (plan §5 rules 1–5) ----------

const COLS = ['O', 'IL', 'IP', 'SV', 'FB', 'FT', 'PP', 'PD'];
const DRAW = {
  IP: ['S15a', 'S15c', 'S15e', 'S15g', 'S15k', 'S15t', 'S15v', 'S10a', 'S10d'],
  SV: ['S15a', 'S15c', 'S15k', 'S15v', 'S10a'],
  FB: ['S15a', 'S15b', 'S15c', 'S15e', 'S15g', 'S15k', 'S15l', 'S15m', 'S15n', 'S15p', 'S15r', 'S15t', 'S15v', 'S10a', 'S10d'],
  FT: ['S15a', 'S15c', 'S15k', 'S15v', 'S10a'],
  PD: ['S15a', 'S10a'],
};
const OVERLAY_STATES = new Set(['S15l', 'S15m', 'S15n', 'S15o', 'S15p', 'S15q', 'S10c', 'S10d', 'S10e']);

function cellPlan(id, col) {
  if (col === 'O' || col === 'IL') return { drawn: true };
  if ((DRAW[col] || []).includes(id)) return { drawn: true };
  const base = id.startsWith('S10') ? 'S10a' : 'S15a';
  const ov = OVERLAY_STATES.has(id);
  switch (col) {
    case 'IP': return ov ? { eq: `${id}·IL`, why: 'overlay, regular (§5.5)' } : { eq: `${base}·IP + column of ${id}·IL` };
    case 'SV': return { eq: `${id}·O`, why: 'compact width; board 320 pt' };
    case 'FB': return ov ? { eq: `${id}·IL, on the right page`, why: 'one FB frame per overlay type (§5.5)' } : { eq: `${base}·FB + column of ${id}·IL` };
    case 'FT': return ov ? { eq: `${id}·IL, below the fold`, why: '§5.5' } : { eq: `${base}·FT + column of ${id}·IP` };
    case 'PP': return { eq: `${id}·IL`, why: 'decision 9' };
    case 'PD': return { eq: `${id}·IL`, why: 'iPad = regular layouts (D11)' };
  }
  return { na: true };
}

// ---------- The layout rule (plan §7) ----------
// Wider than tall → two panes; taller than wide → stacked; an active division
// moves the split onto the fold. Board size comes from the container, never the device.

function geom(k, st) {
  const c = CFG[k === 'FTalt' ? 'FT' : k];
  const ev = !st.noEval && !st.unreadable;
  const compact = c.size.startsWith('C');
  const E = ev ? (compact ? 18 : 20) : 0; // 14 pt eval bar + 4 / 6 pt gap
  const g = { k, c, ev, E, compact };
  if (k === 'O' || k === 'SVL' || k === 'SVR') {
    const x0 = k === 'SVL' ? 84 : k === 'SVR' ? 13.5 : 0;
    const x1 = k === 'SVL' ? 455.5 : k === 'SVR' ? 385 : 382;
    const m = 16;
    g.mode = 'stack'; g.bars = 'side';
    g.title = { x: x0 + m, y: 14, w: x1 - x0 - 2 * m };
    g.B = Math.floor(ev ? x1 - x0 - m - 20 - E + (k === 'O' ? 0 : -1) : x1 - x0 - 2 * m);
    g.boardX = x0 + m + E; g.evalX = x0 + m; g.boardY = 62;
    g.col = { x: x0 + m, y: g.boardY + g.B + 12, w: x1 - x0 - 2 * m };
    g.col.h = c.h - c.bottom - 8 - g.col.y;
    g.content = { x0, x1 };
  } else if (k === 'IL' || k === 'PP') {
    g.mode = 'panes'; g.bars = 'side';
    g.title = { x: 20, y: 14, w: 520 };
    g.B = 504; g.evalX = 20; g.boardX = 20 + E; g.boardY = 62;
    g.col = { x: g.boardX + g.B + 24, y: 62 };
    g.col.w = 867 - 20 - g.col.x; g.col.h = c.h - c.bottom - 8 - g.col.y;
    g.content = { x0: 0, x1: 867 };
  } else if (k === 'FB') {
    g.mode = 'pages'; g.bars = 'side';
    g.title = { x: 20, y: 14, w: 415 };
    g.B = Math.floor((455.5 - 20 - E - 16) / 8) * 8; g.evalX = 20; g.boardX = 20 + E; g.boardY = 62;
    g.col = { x: 495.5 + 4, y: 14 }; g.col.w = 867 - 16 - g.col.x; g.col.h = c.h - c.bottom - 8 - g.col.y;
    g.content = { x0: 0, x1: 867 };
  } else if (k === 'IP') {
    g.mode = 'stack'; g.bars = 'nav';
    g.boardY = 90;
    // stacked: board takes the width but leaves the column at least 240 pt (lines + comment + alternatives fit)
    g.B = Math.min(Math.floor((669 - 40 - E) / 8) * 8, Math.floor((c.h - c.bottom - 48 - 8 - 12 - g.boardY - 240) / 8) * 8);
    g.evalX = (669 - g.B - E) / 2; g.boardX = g.evalX + E;
    g.col = { x: 20, y: g.boardY + g.B + 12, w: 629 }; g.bottomY = c.h - c.bottom - 48;
    g.col.h = g.bottomY - 8 - g.col.y;
    g.content = { x0: 0, x1: 669 };
  } else if (k === 'FT' || k === 'FTalt') {
    g.mode = 'halves'; g.bars = k === 'FT' ? 'nav' : 'fold';
    const top = k === 'FT' ? 82 : 50;
    g.B = Math.floor((373.5 - top - 16) / 8) * 8; g.boardY = top + 8;
    g.evalX = (669 - g.B - E) / 2; g.boardX = g.evalX + E;
    g.bottomY = c.h - c.bottom - 48;
    g.col = { x: 20, y: k === 'FT' ? 413.5 + 8 : 413.5 + 60, w: 629 };
    g.col.h = g.bottomY - 8 - g.col.y;
    g.content = { x0: 0, x1: 669 };
  } else if (k === 'PD') {
    g.mode = 'panes'; g.bars = 'nav';
    g.B = 704; g.evalX = 24; g.boardX = 24 + E; g.boardY = 84;
    g.bottomY = c.h - c.bottom - 50;
    g.col = { x: g.boardX + g.B + 28, y: 84 }; g.col.w = 1194 - 24 - g.col.x; g.col.h = g.bottomY - 8 - g.col.y;
    g.content = { x0: 0, x1: 1194 };
  }
  g.sq = g.B / 8;
  g.tight = g.col.h < 300;
  return g;
}

// ---------- Composer ----------

function toolbarItems(st) {
  const top = [
    { icon: 'chevL', label: st.puzzle ? 'Puzzle' : 'Games' },
  ];
  if (!st.unreadable) {
    top.push({ icon: 'flip', label: 'Flip Board' });
    top.push({ icon: 'lines', label: 'Engine Lines', on: !!st.lines });
  }
  top.push({ icon: 'ellipsis', label: 'More' });
  const bottom = st.unreadable ? [] : [
    { icon: 'chevL', step: true, label: 'Previous Move', disabled: st.empty || st.atStart },
    { icon: 'chevR', step: true, label: 'Next Move', disabled: st.empty },
  ];
  return { top, bottom };
}

function compose(id, k, opts = {}) {
  const st = { ...S[id], ...(opts.st || {}) };
  const gk = k === 'SV' ? 'SVL' : k;
  const g = geom(opts.geomKey || gk, st);
  const cfg = CFG[gk === 'FTalt' ? 'FT' : gk];
  const fs = opts.ax5 ? 2.6 : 1;
  const src = st.puzzle ? PUZZLE : GAME;
  let html = '';
  const tb = toolbarItems(st);

  // bars
  if (g.bars === 'side') {
    html += sideBar(cfg, tb.top, tb.bottom);
  } else if (g.bars === 'nav') {
    html += statusBar(cfg);
    const navY = gk === 'PD' ? 24 : 38;
    html += navBar({ ...cfg }, navY, tb.top[0], `<span style="display:flex;flex-direction:column;align-items:center;line-height:1.15"><span>${src.title}</span><span style="font-size:12px;font-weight:400;color:var(--label2)">${src.sub.split(' · ').slice(0, 2).join(' · ')}</span></span>`, tb.top.slice(1));
    if (tb.bottom.length) html += bottomBar(cfg, g.bottomY + 2, tb.bottom);
  } else if (g.bars === 'fold') {
    // FT alternative: the navigation items move to a bar on the stable half, just below the division
    html += statusBar(cfg);
    html += navBar({ ...cfg }, 413.5 + 8, tb.top[0], src.title, tb.top.slice(1));
    if (tb.bottom.length) html += bottomBar(cfg, g.bottomY + 2, tb.bottom);
  }

  // title (side-bar configurations draw it inline at the top of the content)
  const shift = 0;
  if (g.bars === 'side') {
    // compact: the offline pill shares the title row instead of pushing the board down
    if (st.offline && g.compact) html += abs(g.title.x, g.title.y - 2, g.title.w, 30, banner('offline', 'Offline'), '', 'display:flex;justify-content:flex-end;z-index:2');
    // At AX5 the subtitle doesn't fit above the board; it stays reachable in the overflow menu's header
    html += abs(g.title.x, g.title.y + shift, g.title.w - (st.offline && g.compact ? 96 : 0), 44, fs > 1
      ? `<div class="ttl" style="font-size:28px;line-height:40px">${src.title}</div>`
      : `<div class="ttl">${src.title}</div><div class="sub">${src.sub}</div>`);
  }

  if (st.unreadable) {
    html += unreadable(g, st, cfg);
    return wrap(html, g, st, id, k, opts);
  }

  // board + eval bar
  let B = opts.boardOverride || g.B;
  let boardY = g.boardY + shift;
  if (shift) { B -= shift; }
  const pos = st.promo ? PROMO : st.empty || st.atStart ? { fen: START_FEN, hl: [] } : src;
  const bOpts = { fen: pos.fen, hl: pos.hl, ghost: pos.ghost };
  if (st.missing) { bOpts.mark = { sq: 'f3', label: '+' }; bOpts.hl = ['f3']; }
  if (g.ev) html += abs(g.evalX, boardY, 14, B, evalBar(B, st.starting ? 0.5 : GAME.eval.frac, st.starting ? '–' : GAME.eval.label));
  html += abs(g.boardX, boardY, B, B, board(B, bOpts));

  // column
  const col = { ...g.col };
  if (shift && g.mode === 'stack') { /* board shrank by shift, column keeps its place */ }
  html += column(g, st, col, src, pos, fs, opts);

  // overlays
  html += overlays(g, st, cfg, col, src);
  return wrap(html, g, st, id, k, opts, B);
}

function column(g, st, col, src, pos, fs, opts) {
  let y = col.y, html = '';
  const w = col.w, bottom = col.y + col.h;
  const gap = g.compact ? 8 : 10;
  const rowH = opts.ax5 ? 64 : 34;
  if (st.offline && !g.compact) {
    html += abs(col.x, y, w, 30, banner('offline', 'Offline · changes save when you reconnect'), '', 'display:flex;justify-content:center');
    y += 30 + gap;
  }
  if (st.problem) {
    html += abs(col.x, y, w, 36, `<div class="problem">Illegal move in the PGN at 14. Nxe5. Later moves aren't shown.</div>`);
    y += 36 + 4;
  }
  if (st.promo) {
    const ps = ['q', 'r', 'b', 'n'].map((p, i) => `<span class="promo-btn ${i === 0 ? 'on' : ''}">${PIECE[p]}&#xFE0E;</span>`).join('');
    html += abs(col.x, y, w, 80, `<div class="promo-h">PROMOTE TO</div><div class="promo">${ps}</div>`);
    y += 80 + gap;
  }
  if (st.alts && !st.empty) {
    const a = altChips(w, GAME.alts, st.altsOpen, 15 * Math.min(fs, 1.6), g.tight && !st.altsOpen);
    html += abs(col.x, y, w, a.h, a.html); y += a.h + gap;
  }
  if (st.lines) {
    const lp = linesPanel(w, GAME.lines, { starting: st.starting, rowH: g.tight ? 28 : 34, head: g.tight ? 26 : 30, rows: opts.ax5 ? 2 : 3 });
    html += abs(col.x, y, w, lp.h, lp.html); y += lp.h + gap;
  }
  if (st.comment) {
    const cm = commentCard(w, GAME.comment, g.tight && st.lines ? 1 : 3, 15 * Math.min(fs, 1.8));
    html += abs(col.x, y, w, cm.h, cm.html); y += cm.h + gap;
    g.overflow = y - gap > bottom;
  }
  // In a short column (O, SV, IP) the engine lines replace the move list (decision 5, option A)
  if (!(g.tight && st.lines)) {
    let rows = st.promo ? PROMO.rows : src.rows.map((r) => ({ ...r }));
    if (st.atStart) rows = rows.map((r) => ({ ...r, sel: undefined }));
    if (st.problem) rows = rows.slice(0, 13);
    if (st.vari) rows.splice(GAME.vari.after + 1, 0, { vari: true, text: GAME.vari.text });
    if (st.overlay === 'ctx' || st.overlay === 'delmove') rows = rows.map((r) => (r.n === 6 ? { ...r, ctx: 'w' } : r));
    const ml = moveList(w, Math.max(0, bottom - y), rows, { rowH, fs: 17 * Math.min(fs, 2.8), empty: st.empty ? 'No moves yet. Drag a piece to start.' : null });
    html += abs(col.x, y, w, ml.h, ml.html);
    g.moveRows = st.empty ? 0 : ml.fit;
    g.ctxRowY = y + 5 * rowH + rowH / 2;
  } else g.moveRows = 0;
  return html;
}

function unreadable(g, st, cfg) {
  // ContentUnavailableView, kept to the readable width (F13); on FB it stays on the right page
  let x0 = g.content.x0, x1 = g.content.x1;
  if (g.mode === 'pages') x0 = 495.5;
  const w = Math.min(672, x1 - x0 - 40);
  const x = x0 + (x1 - x0 - w) / 2;
  let y = g.bars === 'nav' ? 110 : 80;
  let html = '';
  if (st.offline) { html += abs(x, y - 40, w, 30, banner('offline', 'Offline'), '', 'display:flex;justify-content:center'); }
  html += abs(x, y, w, 120, `<div class="cuv"><div style="display:flex;justify-content:center;color:var(--label2)">${icon('warn', 44, 1.8)}</div><b>Can't Read This Game</b>The PGN has a problem Motif can't fix. Here it is as stored.</div>`);
  html += abs(x, y + 140, w, 180, `<div class="pgnbox">[Event "Club championship"]<br>[White "Me"]<br>[Black "Club friend"]<br>[Result "1-0"]<br><br>1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Na5 10. Bc2 c5 11. d4 {unclosed comment 12. Nbd2</div>`);
  return html;
}

function overlays(g, st, cfg, col, src) {
  const o = st.overlay;
  if (!o) return '';
  let html = '';
  const sideX = cfg.side ? (cfg.side.edge === 'R' ? cfg.w - cfg.side.w : cfg.side.w) : null;
  const regular = !g.compact;
  // Menu anchored to its toolbar item; on the side bar it opens beside the bar (Phase 1)
  const menuAt = (w, h) => {
    if (g.bars === 'side') return { x: sideX - w - 8, y: 186 + 3 * 52 - 10 };
    return { x: cfg.w - 12 - w, y: 90 };
  };
  if (o === 'menu' || o === 'pmenu') {
    const secs = o === 'menu' ? [
      [{ label: 'Save', icon: 'save', disabled: st.offline }, { label: 'Edit Details', icon: 'pencil' }, { label: 'Add Comment', icon: 'bubble' }],
      [{ label: 'Hide Evaluation', icon: 'eyeSlash' }],
      [{ label: 'Copy PGN', icon: 'doc' }, { label: 'Export PGN…', icon: 'share' }],
      [{ label: 'Delete Game', icon: 'trash', role: 'destructive' }],
    ] : [
      [{ label: 'Save as Game…', icon: 'save', disabled: st.offline }],
      [{ label: 'Hide Evaluation', icon: 'eyeSlash' }],
      [{ label: 'Copy PGN', icon: 'doc' }, { label: 'Export PGN…', icon: 'share' }],
    ];
    const w = 250;
    const p = menuAt(w);
    const m = menu(p.x, p.y, w, secs);
    let y = p.y;
    if (y + m.h > cfg.h - cfg.bottom) y = cfg.h - cfg.bottom - m.h;
    html += menu(p.x, y, w, secs).html;
  }
  if (o === 'ctx') {
    const w = 250;
    const x = Math.min(col.x + 40, cfg.w - (cfg.side ? cfg.side.w : 0) - w - 8);
    let y = g.ctxRowY + 24;
    const m = menu(0, 0, w, [[{ label: 'Add Comment', icon: 'bubble' }], [{ label: 'Delete From Here', sub: '17 moves', icon: 'trash', role: 'destructive' }]]);
    if (y + m.h > cfg.h - cfg.bottom) y = g.ctxRowY - 24 - m.h;
    html += abs(0, 0, cfg.w, cfg.h, '', 'dimmer', 'z-index:44;-webkit-backdrop-filter:blur(3px);backdrop-filter:blur(3px)');
    html += menu(x, y, w, [[{ label: 'Add Comment', icon: 'bubble' }], [{ label: 'Delete From Here', sub: '17 moves', icon: 'trash', role: 'destructive' }]]).html;
  }
  if (o === 'delmove' || o === 'delgame') {
    const title = o === 'delmove' ? 'Delete from 6. Re1?' : 'Delete this game?';
    const msg = o === 'delmove' ? 'This deletes 17 moves and their comments.' : 'It is removed from Club games on all your devices.';
    const act = [{ label: o === 'delmove' ? 'Delete 17 Moves' : 'Delete Game', role: 'destructive' }];
    if (regular) {
      // popover anchored to the source that asked: the move row, or the overflow button
      if (o === 'delmove') html += popover(col.x + 110, g.ctxRowY, g.mode === 'pages' || g.mode === 'panes' ? 'below' : 'below', title, msg, act);
      else html += popover(sideX != null ? sideX : cfg.w - 34, sideX != null ? 186 + 3 * 52 + 22 : 60, sideX != null ? 'left' : 'below', title, msg, act);
    } else {
      const x0 = g.content.x0 + 8, x1 = g.content.x1 - 8;
      html += dim(cfg) + actionSheet(x0, x1 - x0, cfg.h - cfg.bottom - 4, title, msg, act);
    }
  }
  if (o === 'unsaved' || o === 'unsavedOff') {
    let cx = g.mode === 'pages' ? 495.5 + (867 - 495.5) / 2 : g.content.x0 + (g.content.x1 - g.content.x0) / 2;
    let cy = g.mode === 'halves' ? 413.5 + 200 : cfg.h / 2;
    html += dim(cfg);
    html += o === 'unsaved'
      ? alertBox(cx, cy, 'Save changes to this game?', 'You made 3 moves that aren\'t saved.', [{ label: 'Save', role: 'primary' }, { label: 'Discard', role: 'destructive' }, { label: 'Cancel' }], true)
      : alertBox(cx, cy, 'You\'re offline', 'Changes can\'t be saved until you\'re back online.', [{ label: 'Discard Changes', role: 'destructive' }, { label: 'Keep Editing' }], true);
  }
  if (o === 'save' || o === 'saveNew') html += saveSheet(g, st, cfg, o === 'saveNew');
  return html;
}

function saveSheet(g, st, cfg, isNew) {
  const rows = [
    { label: 'Club games', value: '24 games', sel: !isNew },
    { label: 'Openings', value: '9 games' },
    { label: 'New Collection…', value: '', sel: isNew },
  ];
  const body = `<div class="form-h">SAVE TO</div>${formRows(rows)}` + (isNew ? `<div class="form-h">NAME</div><div class="field">Tactics from puzzles<span class="caret"></span></div>` : '');
  const contentH = 64 + 26 + rows.length * 48 + (isNew ? 26 + 48 : 0) + 24;
  let html = '';
  const kbH = isNew ? (g.compact ? 313 : 289) : 0;
  if (g.compact) {
    // fitted detent (F17, F29): the sheet only takes what it needs; ✕ and ✓ in the side bar (Phase 1)
    const x = (g.content.x0 || 0) + 8, w = 450 - (g.content.x0 ? 0 : 0);
    const sw = (g.content.x1 - g.content.x0) - 16 + (cfg.side ? 84 - 8 : 0);
    const y = cfg.h - 8 - contentH - kbH;
    html += dim(cfg);
    html += sheet(8, y, cfg.w - 16 - (cfg.side ? 0 : 0) - (cfg.side ? 76 : 0), contentH, 'Save as Game', body, { sideControls: true, grabber: true });
    html += abs(cfg.w - cfg.side.w + 20, y + 10, 44, 44, icon('xmark', 19), 'tb', 'z-index:47');
    html += abs(cfg.w - cfg.side.w + 20, y + 62, 44, 44, icon('check', 20), 'tb on', 'z-index:47');
  } else {
    // centered form sheet sized to its content (presentationSizing .form.fitted); on FB it moves to one page
    let w = 520, x, y;
    if (g.mode === 'pages') { w = 440; x = 8; y = 30; } else { x = (cfg.w - (cfg.side ? cfg.side.w : 0) - w) / 2; y = Math.max(30, (cfg.h - contentH - kbH) / 2 - (kbH ? 40 : 0)); }
    if (g.mode === 'halves') y = 413.5 + 20;
    html += dim(cfg) + sheet(x, y, w, contentH, 'Save as Game', body);
  }
  const kl = (t) => `<div style="padding:14px;color:var(--label2);font-size:13px;text-align:center">${t}</div>`;
  if (kbH && g.compact) html += abs(0, cfg.h - kbH, cfg.w, kbH, kl('Keyboard 313 pt'), 'kbd');
  else if (kbH) { html += abs(0, cfg.h - kbH, 360, kbH, kl('Split keyboard 289 pt'), 'kbd', 'border-top-right-radius:18px'); html += abs(cfg.w - 360, cfg.h - kbH, 360, kbH, kl('Split keyboard 289 pt'), 'kbd', 'border-top-left-radius:18px'); }
  return html;
}

function wrap(html, g, st, id, k, opts, B) {
  const chips = [];
  const cfg = CFG[k === 'SV' ? 'SVL' : k === 'FTalt' ? 'FT' : k];
  chips.push({ text: cfg.size });
  chips.push({ text: `bars: ${g.bars === 'side' ? cfg.bars + ' side bar' : g.bars === 'fold' ? 'below the fold' : 'top + bottom'}` });
  chips.push({ text: `NavigationSplitView · .prominentDetail › AnyLayout(${g.mode === 'stack' || g.mode === 'halves' ? 'VStack' : 'HStack'})`, kind: 'ct' });
  if (!st.unreadable) {
    const sq = (B || g.B) / 8;
    const ok = sq >= MIN_TARGET;
    chips.push({ text: `board ${Math.round(B || g.B)} pt · ${sq.toFixed(1)} pt squares`, kind: ok ? '' : 'exc' });
    if (!ok) chips.push({ text: g.compact ? '§6.6 exception: decision 5' : '§6.6 exception: open (Q1)', kind: 'exc' });
    if (g.moveRows != null && !(g.tight && st.lines)) chips.push({ text: `${g.moveRows} move rows` });
  }
  if (g.overflow) chips.push({ text: 'column overflows: fix', kind: 'exc' });
  if (g.mode === 'pages') chips.push({ text: 'board on the left page, nothing on the division', kind: 'fix' });
  if (g.mode === 'halves') chips.push({ text: 'board above the division, controls below', kind: 'fix' });
  (opts.chips || []).forEach((c) => chips.push(c));
  const cls = (opts.rt ? 'rt ' : '') + (opts.ax5 ? 'ax5' : '');
  const fid = opts.fid || `${id}·${k}`;
  return frame(fid, k === 'SV' ? 'SVL' : k === 'FTalt' ? 'FT' : k, html, chips, { caption: opts.caption || S[id].t, cls });
}

function composeSVR(id) {
  return compose(id, 'SVR', { geomKey: 'SVR', fid: `${id}·SV (right)` });
}

// ---------- Page ----------

function renderCanvas(prefix) {
  let out = '';
  STATES.filter((s) => s.id.startsWith(prefix)).forEach((s) => {
    out += `<div class="state-row"><div class="state-label"><b>${s.id}</b>${s.t}</div>`;
    COLS.forEach((col) => {
      const p = cellPlan(s.id, col);
      if (p.drawn) {
        if (col === 'SV') {
          out += compose(s.id, 'SV', { fid: `${s.id}·SV` + (s.id === 'S15a' ? ' (left)' : '') });
          if (s.id === 'S15a') out += composeSVR(s.id);
        } else out += compose(s.id, col);
        if (col === 'FT' && s.id === 'S15a') out += compose('S15a', 'FTalt', { geomKey: 'FTalt', fid: 'S15a·FT (alt)', caption: 'Alternative for Q1: nav items below the fold', chips: [{ text: 'toolbarVisibility(.hidden) top; items in a bar on the stable half', kind: 'ct' }] });
      } else {
        out += `<div class="eqcell"><b>${s.id}·${col}</b>${p.eq ? '= ' + p.eq : 'n/a'}${p.why ? `<br><i>${p.why}</i>` : ''}</div>`;
      }
    });
    out += '</div>';
  });
  return out;
}

function renderVariants() {
  let out = '<div class="state-row"><div class="state-label"><b>AX5</b>Dynamic Type AX5 (§5.6)</div>';
  out += compose('S15a', 'O', { ax5: true, fid: 'S15a·O·AX5', caption: 'AX5' });
  out += compose('S15a', 'IL', { ax5: true, fid: 'S15a·IL·AX5', caption: 'AX5' });
  out += compose('S10a', 'O', { ax5: true, fid: 'S10a·O·AX5', caption: 'AX5' });
  out += compose('S10a', 'IL', { ax5: true, fid: 'S10a·IL·AX5', caption: 'AX5' });
  out += '</div><div class="state-row"><div class="state-label"><b>RT</b>Reduce Transparency (§5.6)</div>';
  out += compose('S15c', 'O', { rt: true, fid: 'S15a·O·RT', caption: 'Reduce Transparency (lines on, to show the panels)', st: {} });
  out += compose('S15e', 'IL', { rt: true, fid: 'S15a·IL·RT', caption: 'Reduce Transparency (comment on)' });
  out += compose('S10a', 'O', { rt: true, fid: 'S10a·O·RT', caption: 'Reduce Transparency' });
  out += compose('S10a', 'IL', { rt: true, fid: 'S10a·IL·RT', caption: 'Reduce Transparency' });
  out += '</div>';
  return out;
}

function renderStoryboards() {
  let out = '';
  out += `<h2>Unfold with unsaved moves (S15p)</h2><div class="story">`;
  out += compose('S15p', 'O', { fid: '1 · closed', caption: 'Back alert open, 3 unsaved moves, 3… a6 selected' });
  out += '<span class="arrow">→</span>';
  out += compose('S15p', 'FB', { fid: '2 · opening (90°)', caption: 'Same GameViewModel; AnyLayout swaps to pages; alert stays presented, moves to the right page' });
  out += '<span class="arrow">→</span>';
  out += compose('S15p', 'IL', { fid: '3 · open', caption: 'Alert centered; selection, path and unsaved moves kept. Focus stays on the alert' });
  out += '</div>';
  out += `<h2>Bend open → book with engine lines (S15c)</h2><div class="story">`;
  out += compose('S15c', 'IL', { fid: '1 · flat', caption: 'Two panes; board may cross the inactive fold' });
  out += '<span class="arrow">→</span>';
  out += compose('S15c', 'FB', { fid: '2 · division turns active', caption: 'System animation: board shrinks toward the left page', boardOverride: 448, chips: [{ text: 'mid-animation, not a resting state', kind: 'exc' }] });
  out += '<span class="arrow">→</span>';
  out += compose('S15c', 'FB', { fid: '3 · book', caption: 'Board on the left page; lines, moves and controls on the right' });
  out += '</div>';
  return out;
}

function renderCoverage() {
  let rows = '';
  let drawn = 0, eq = 0;
  STATES.forEach((s) => {
    rows += `<tr><th style="text-align:left">${s.id} <span style="font-weight:400">${s.t}</span></th>`;
    COLS.forEach((col) => {
      const p = cellPlan(s.id, col);
      if (p.drawn) { drawn++; rows += `<td class="drawn"><a href="#${s.id}·${col}">●</a></td>`; }
      else if (p.eq) { eq++; rows += `<td class="eq">= ${p.eq}</td>`; }
      else rows += `<td class="na">n/a</td>`;
    });
    rows += '</tr>';
  });
  return `<p>${STATES.length} states × ${COLS.length} configurations = ${STATES.length * COLS.length} cells: <b>${drawn} drawn</b>, ${eq} equal to a drawn frame, 0 blank. Plus 8 system-variant frames, 6 storyboard frames, 2 extra (S15a·SV right, S15a·FT alt). ST is dropped (decision 8).</p>
  <table class="cov"><tr><th></th>${COLS.map((c) => `<th>${c}</th>`).join('')}</tr>${rows}</table>`;
}

if (typeof module !== 'undefined') module.exports = { geom, STATES };
