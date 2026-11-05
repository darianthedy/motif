// Session and detail canvas (S09 Session, S08 Puzzle detail). Plan §5, §7.
// Same layout rule as the Analysis canvas (boardGeom in kit.js), no eval bar.

const PZ = {
  fen: '6k1/5ppp/8/8/8/8/5PPP/R3R1K1 w - - 0 1',
  replyFen: 'R5k1/5ppp/8/8/8/8/5PPP/4R1K1 b - - 0 1',
  missingFen: '2r3k1/5ppp/8/3Q4/8/8/5PPP/6K1 w - - 0 1',
  promoFen: '8/4P1k1/8/5K2/8/8/8/8 w - - 0 60',
  comment: 'The luft is the whole puzzle. Black never made one.',
  long: 'The luft is the whole puzzle. Black never made one, and both rooks are ready to use the open files. In the game Black played 1… h6 one move too late: after 1. Re8+ Kh7 2. Ra8 the threat on the eighth rank is decisive anyway. Compare puzzle #4, where the same pattern works only because the bishop covers g8. This one is from the 2019 club championship, round 5.',
  tags: 'Back rank · Mate in 1',
};

const STATES = [
  { id: 'S09a', t: 'Your move', kind: 'session' },
  { id: 'S09b', t: 'Wrong move', kind: 'session', wrong: true },
  { id: 'S09c', t: 'Answer shown', kind: 'session', hint: true },
  { id: 'S09d', t: 'Opponent replying', kind: 'session', replying: true },
  { id: 'S09e', t: 'Promotion picker', kind: 'session', picker: 'promo' },
  { id: 'S09f', t: 'Missing piece: tap square', kind: 'session', missing: 'tap' },
  { id: 'S09g', t: 'Missing piece: choose piece', kind: 'session', missing: 'choose', picker: 'missing' },
  { id: 'S09h', t: 'Missing piece: hint', kind: 'session', missing: 'hint' },
  { id: 'S09i', t: 'Solved', kind: 'session', result: 'solved' },
  { id: 'S09j', t: 'Solved, several lines', kind: 'session', result: 'lines' },
  { id: 'S09k', t: 'Missed', kind: 'session', result: 'missed' },
  { id: 'S09l', t: 'Long result (card scrolls)', kind: 'session', result: 'long' },
  { id: 'S09m', t: 'Session complete', kind: 'session', complete: true },
  { id: 'S09n', t: 'Flagged', kind: 'session', flagged: true },
  { id: 'S09o', t: 'Offline', kind: 'session', offline: true },
  { id: 'S08a', t: 'Move puzzle at start', kind: 'detail' },
  { id: 'S08b', t: 'Stepping a solution', kind: 'detail', ply: 1 },
  { id: 'S08c', t: 'Several solution lines', kind: 'detail', lines: true, ply: 1 },
  { id: 'S08d', t: 'Missing piece', kind: 'detail', missing: 'answer' },
  { id: 'S08e', t: 'Flagged', kind: 'detail', flagged: true },
  { id: 'S08f', t: 'Overflow menu', kind: 'detail', overlay: 'menu' },
  { id: 'S08g', t: 'Comment sheet', kind: 'detail', overlay: 'comment' },
  { id: 'S08h', t: 'Delete confirmation', kind: 'detail', overlay: 'delete' },
  { id: 'S08i', t: 'Offline', kind: 'detail', offline: true },
];
const S = Object.fromEntries(STATES.map((s) => [s.id, s]));

const COLS = ['O', 'IL', 'IP', 'SV', 'FB', 'FT', 'PP', 'PD'];
const DRAW = {
  IP: ['S09a', 'S09e', 'S09i', 'S09l', 'S09m', 'S08a', 'S08c', 'S08g'],
  SV: ['S09a', 'S09i', 'S08a'],
  FB: ['S09a', 'S09e', 'S09g', 'S09i', 'S09j', 'S09k', 'S09l', 'S09m', 'S08a', 'S08c', 'S08d', 'S08f', 'S08g', 'S08h'],
  FT: ['S09a', 'S09e', 'S09i', 'S09m', 'S08a', 'S08c'],
  PD: ['S09a', 'S08a'],
};
const OVERLAY_STATES = new Set(['S08f', 'S08g', 'S08h']);

function cellPlan(id, col) {
  if (col === 'O' || col === 'IL') return { drawn: true };
  if ((DRAW[col] || []).includes(id)) return { drawn: true };
  const base = id.startsWith('S08') ? 'S08a' : id === 'S09m' ? 'S09m' : 'S09a';
  const ov = OVERLAY_STATES.has(id);
  const isResult = ['S09i', 'S09j', 'S09k', 'S09l'].includes(id);
  switch (col) {
    case 'IP': return ov ? { eq: `${id}·IL`, why: 'overlay, regular (§5.5)' } : { eq: `${isResult ? 'S09i' : base}·IP + column of ${id}·IL` };
    case 'SV': return { eq: `${id}·O`, why: 'compact width; board 336 pt' };
    case 'FB': return ov ? { eq: `${id}·IL, on the right page` } : { eq: `${base}·FB + column of ${id}·IL` };
    case 'FT': return ov ? { eq: `${id}·IL, below the fold` } : { eq: `${isResult ? 'S09i' : base}·FT + column of ${id}·IP` };
    case 'PP': return { eq: `${id}·IL`, why: 'decision 9' };
    case 'PD': return { eq: `${id}·IL`, why: 'iPad = regular layouts (D11)' };
  }
  return { na: true };
}

// ---------- Blocks ----------

function prompt(guidance, warn, side = 'White') {
  return `<span class="glass prompt${warn ? ' warn' : ''}"><span class="dot" style="background:${side === 'White' ? '#fff' : '#000'}"></span><span style="display:flex;flex-direction:column"><span class="side">${side} to move</span><span class="guide">${guidance}</span></span></span>`;
}

function pickerCard(w, kind) {
  const pieces = kind === 'promo' ? [['q', 'Queen'], ['r', 'Rook'], ['b', 'Bishop'], ['n', 'Knight']] : [['q', 'Queen'], ['r', 'Rook'], ['b', 'Bishop'], ['n', 'Knight'], ['p', 'Pawn']];
  const title = kind === 'promo' ? 'Promote to' : 'Which piece is missing?';
  const h = 16 + 22 + 12 + 64 + 12 + 34 + 16;
  return { html: `<div class="glass picker" style="width:${w}px;height:${h}px"><h4>${title}</h4><div class="pk-row">${pieces.map(([p, n]) => `<span class="pk"><span class="g">${PIECE[p]}&#xFE0E;</span>${n}</span>`).join('')}</div><span class="pk-cancel">Cancel</span></div>`, h };
}

function resultCard(w, kind, maxH) {
  const ok = kind !== 'missed';
  let body = `<div class="rs-verdict ${ok ? 'ok' : 'bad'}">${icon(ok ? 'checkCircle' : 'xCircle', 24, 2.2)}${ok ? 'Solved' : 'Missed'}</div>`;
  let h = 40 + 26;
  if (kind === 'missed') { body += `<div class="rs-miss">1st  Ra7 · Rd1 → Ra8#</div>`; h += 20 + 12; }
  if (kind === 'lines') {
    body += `<div class="rs-line"><span class="n">1</span>1. Ra8#<span class="yours">Your line</span></div><div class="rs-line"><span class="n">2</span>1. Re8+ Kh7?? 2. Ra… — 1. Re8#</div>`;
    h += 2 * 22 + 24;
  } else { body += `<div class="rs-line">1. Ra8#${ok ? '<span class="yours">Your line</span>' : ''}</div>`; h += 22 + 12; }
  const text = kind === 'long' ? PZ.long : PZ.comment;
  const cpl = Math.max(20, Math.floor((w - 40) / 8.6));
  const lines = Math.ceil(text.length / cpl);
  body += `<div class="rs-comment">${text}</div><div class="rs-tags">${PZ.tags}</div>`;
  h += lines * 22 + 12 + 18 + 12;
  h += 50 + 12;
  const natural = h;
  let clip = false;
  if (maxH && h > maxH) { h = maxH; clip = true; }
  const btns = `<div class="rs-btns"><span class="btn glassbtn">${icon('search', 18)}Analyze</span><span class="btn prom">Continue</span></div>`;
  return { html: `<div class="glass result" style="width:${w}px;height:${h}px"><div class="rs-scroll${clip ? ' clip' : ''}">${body}${clip ? '<span class="rs-bar"></span>' : ''}</div>${btns}</div>`, h, natural, clip };
}

function solChips(w, ply) {
  const chips = ['1. Ra8#'];
  return { html: `<div class="solchips" style="width:${w}px;height:44px">${chips.map((c, i) => `<span class="chip${ply === i + 1 ? ' on' : ''}" style="font-size:15px">${c}</span>`).join('')}</div>`, h: 44 };
}

function infoList(w, st) {
  const rows = [];
  if (st.missing === 'answer') rows.push(`<div class="gl-row"><span>Answer</span><span class="v">White knight on f6</span></div>`);
  rows.push(`<div class="gl-row"><span class="l"><span>Status</span><span class="s">2 attempts · 1 mistake</span></span><span class="v">Learning</span></div>`);
  rows.push(`<div class="gl-row"><span>Motif</span><span class="v">Back rank, Mate in 1</span></div>`);
  rows.push(`<div class="gl-row"><span>Rating</span><span class="v">800</span></div>`);
  rows.push(`<div class="gl-row${st.offline ? ' dis' : ''}"><span class="l"><span>Comment</span><span class="s" style="max-width:${w - 70}px">${PZ.comment}</span></span><span class="v">›</span></div>`);
  const h = (st.missing === 'answer' ? 44 : 0) + 64 + 44 + 44 + 64;
  return { html: `<div class="glist" style="width:${w}px">${rows.join('')}</div>`, h };
}

// ---------- Composer ----------

function toolbar(st) {
  if (st.kind === 'session') {
    const top = [{ icon: 'xmark', label: 'End Session' }];
    if (!st.complete) top.push({ icon: st.flagged ? 'flagFill' : 'flag', label: st.flagged ? 'Unflag' : 'Flag', cls: st.flagged ? 'flagged' : '', disabled: st.offline });
    const bottom = st.result || st.complete ? [] : [{ icon: 'skip', text: 'Skip', label: 'Skip' }];
    return { top, bottom };
  }
  return {
    top: [{ icon: 'chevL', label: 'Back-rank mates' }, { icon: st.flagged ? 'flagFill' : 'flag', label: 'Flag', cls: st.flagged ? 'flagged' : '', disabled: st.offline }, { icon: 'ellipsis', label: 'More' }],
    bottom: st.missing ? [] : [{ icon: 'toStart', step: true, disabled: !st.ply }, { icon: 'chevL', step: true, disabled: !st.ply }, { icon: 'chevR', step: true, disabled: !!st.ply }, { icon: 'toEnd', step: true, disabled: !!st.ply }],
  };
}

function compose(id, k, opts = {}) {
  const st = { ...S[id], ...(opts.st || {}) };
  const gk = opts.geomKey || (k === 'SV' ? 'SVL' : k);
  const g = boardGeom(gk, { noEval: true });
  const cfg = CFG[gk === 'FTalt' ? 'FT' : gk];
  const tb = toolbar(st);
  const title = st.kind === 'session' ? 'Random' : '#1';
  const sub = st.kind === 'session' ? (st.complete ? '' : 'Puzzle 3 of 6') : 'Back-rank mates';
  const fs = opts.ax5 ? 2.4 : 1;
  let html = '';

  if (g.bars === 'side') html += sideBar(cfg, tb.top, tb.bottom);
  else {
    html += statusBar(cfg);
    html += navBar(cfg, gk === 'PD' ? 24 : 38, tb.top[0], `<span style="display:flex;flex-direction:column;align-items:center;line-height:1.15"><span>${title}</span><span style="font-size:12px;font-weight:400;color:var(--label2)">${sub}</span></span>`, tb.top.slice(1));
    if (tb.bottom.length) html += bottomBar(cfg, g.bottomY + 2, tb.bottom);
  }

  // title + progress
  let tx = g.title ? g.title.x : 20, tw = g.title ? g.title.w : cfg.w - 40;
  if (g.bars === 'side') {
    if (st.offline && g.compact) html += abs(tx, 12, tw, 30, banner('offline', 'Offline'), '', 'display:flex;justify-content:flex-end;z-index:2');
    html += abs(tx, 14, tw - (st.offline && g.compact ? 96 : 0), 44, fs > 1 ? `<div class="ttl" style="font-size:28px;line-height:40px">${title}</div>` : `<div class="ttl">${title}</div><div class="sub">${sub}</div>`);
  }
  const dy = st.kind === 'session' ? 6 : 0;
  if (st.kind === 'session' && !st.complete) {
    const py = g.bars === 'side' ? 58 : (gk === 'PD' ? 78 : 86);
    const pw = g.bars === 'side' ? (g.mode === 'panes' ? g.B : tw) : cfg.w - 40;
    html += abs(g.bars === 'side' ? tx : 20, py, pw, 4, '<span style="width:42%"></span>', 'progress');
  }

  if (st.complete) { html += complete(g, cfg, st); return wrap(html, g, st, id, k, opts, null, cfg); }

  // board
  const B = g.B;
  const by = g.boardY + dy;
  const bo = { fen: PZ.fen, hl: [] };
  if (st.wrong) { bo.hl = ['a1', 'a7']; bo.flash = ['a7']; }
  if (st.hint) { bo.hl = ['a1', 'a8']; bo.hint = true; }
  if (st.replying) { bo.fen = PZ.replyFen; bo.hl = ['a1', 'a8']; }
  if (st.picker === 'promo') { bo.fen = PZ.promoFen; bo.hl = ['e7', 'e8']; bo.ghost = { sq: 'e8', piece: 'q' }; }
  if (st.missing) bo.fen = PZ.missingFen;
  if (st.missing === 'choose') bo.select = 'f6';
  if (st.missing === 'hint') { bo.hl = ['f6']; bo.hint = true; }
  if (st.missing === 'answer') { bo.fen = PZ.missingFen.replace('8/3Q4', '5N2/3Q4'); bo.hl = ['f6']; }
  if (st.result) { bo.fen = PZ.replyFen.replace(' b ', ' w '); bo.hl = ['a1', 'a8']; }
  if (st.kind === 'detail' && st.ply) { bo.fen = PZ.replyFen; bo.hl = ['a1', 'a8']; }
  html += abs(g.boardX, by, B, B, board(B, bo));

  // column
  const col = { ...g.col, y: g.col.y + dy, h: g.col.h - dy };
  const gap = 12;
  let y = col.y;
  if (st.offline && !g.compact) { html += abs(col.x, y, col.w, 30, banner('offline', 'Offline · results upload later'), '', 'display:flex;justify-content:flex-start'); y += 42; }

  if (st.kind === 'session') {
    const guidance = st.wrong ? 'Not quite.' : st.hint ? 'Not quite. Play the highlighted move.' : st.replying ? 'Opponent is replying…' : st.missing === 'tap' ? 'Tap the square where a piece is missing.' : st.missing === 'hint' ? 'Not quite. Add the knight on the orange square.' : st.missing === 'choose' ? 'Choose the piece for f6.' : 'Find the best move.';
    if (!st.result && !st.picker) { html += abs(col.x, y, col.w, 56, prompt(guidance, st.wrong || st.hint || st.missing === 'hint'), '', `display:flex;justify-content:${g.mode === 'stack' || g.mode === 'halves' ? 'center' : 'flex-start'}`); y += 56 + gap; }
    if (st.picker) { const w = Math.min(col.w, 380); const p = pickerCard(w, st.picker); html += abs(col.x + (g.mode === 'stack' || g.mode === 'halves' ? (col.w - w) / 2 : 0), y, w, p.h, p.html); y += p.h + gap; g.pickerBottom = y; }
    if (st.result) {
      if (g.mode === 'stack' && g.bars === 'side') {
        // compact: the card rises from the bottom, sized to its content, capped at 62 % of the height
        const x0 = g.content.x0 + 8, w = g.content.x1 - g.content.x0 - 16;
        const r = resultCard(w, st.result, Math.round(cfg.h * 0.62));
        const ry = cfg.h - cfg.bottom - r.h;
        html += abs(x0, ry, w, r.h, r.html);
        g.cover = Math.max(0, by + B - ry); g.cardH = r.h; g.clip = r.clip;
      } else {
        const w = Math.min(col.w, 560);
        const avail = (g.mode === 'stack' || g.mode === 'halves' ? g.bottomY + 46 : col.y + col.h) - y;
        const r = resultCard(w, st.result, avail);
        const ry = g.mode === 'stack' || g.mode === 'halves' ? Math.max(y, g.bottomY + 46 - r.h) : y;
        html += abs(col.x + (g.mode === 'stack' || g.mode === 'halves' ? (col.w - w) / 2 : 0), ry, w, r.h, r.html);
        g.cover = g.mode === 'stack' || g.mode === 'halves' ? Math.max(0, by + B - ry) : 0; g.cardH = r.h; g.clip = r.clip;
      }
    }
  } else {
    if (st.lines) { html += abs(col.x, y, Math.min(col.w, 360), 36, `<div class="seg"><span class="on">Line 1</span><span>Line 2</span></div>`); y += 36 + gap; }
    if (!st.missing) { const c = solChips(col.w, st.ply); html += abs(col.x, y, col.w, c.h, c.html); y += c.h + gap; }
    const il = infoList(col.w, st);
    const avail = col.y + col.h - y;
    html += abs(col.x, y, col.w, Math.min(il.h, avail), il.html, il.h > avail ? 'scrollfade' : '', 'overflow:hidden');
    g.listClipped = il.h > avail;
    html += overlays(g, st, cfg, col);
  }
  return wrap(html, g, st, id, k, opts, B, cfg);
}

function complete(g, cfg, st) {
  const icon72 = `<div style="color:var(--accent-fill);display:flex;justify-content:center">${icon('checkCircle', 72)}</div>`;
  const head = `${icon72}<div style="text-align:center;font-size:28px;font-weight:700;margin-top:16px">Session Complete</div>`;
  const tiles = `<div class="tiles"><div class="tile"><b style="color:var(--accent)">5</b><span>Solved cleanly</span></div><div class="tile"><b style="color:#c93400">1</b><span>Missed</span></div></div>`;
  const done = `<span class="btn prom" style="display:flex">Done</span>`;
  let html = '';
  if (g.mode === 'pages') {
    html += abs(20, 220, 415, 140, head);
    html += abs(515, 200, 332, 100, tiles) + abs(515, 560, 332, 50, done);
  } else if (g.mode === 'halves') {
    html += abs(0, 160, cfg.w, 140, head);
    const w = 480, x = (cfg.w - w) / 2;
    html += abs(x, 450, w, 100, tiles) + abs(x, g.bottomY - 10, w, 50, done);
  } else {
    const x0 = g.content.x0, x1 = g.content.x1;
    const w = Math.min(480, x1 - x0 - 40), x = x0 + (x1 - x0 - w) / 2;
    const top = (g.bars === 'side' ? 0 : 90) + (cfg.h - cfg.bottom - (g.bars === 'side' ? 0 : 90)) * 0.22;
    html += abs(x0, top, x1 - x0, 140, head) + abs(x, top + 160, w, 100, tiles);
    html += abs(x, cfg.h - cfg.bottom - 16 - 50, w, 50, done);
  }
  return html;
}

function overlays(g, st, cfg, col) {
  const o = st.overlay;
  if (!o) return '';
  let html = '';
  const sideX = cfg.side ? (cfg.side.edge === 'R' ? cfg.w - cfg.side.w : cfg.side.w) : null;
  if (o === 'menu') {
    const secs = [[{ label: 'Copy FEN', icon: 'doc' }], [{ label: 'Delete Puzzle', icon: 'trash', role: 'destructive', disabled: st.offline }]];
    const w = 230;
    const p = g.bars === 'side' ? { x: sideX - w - 8, y: 186 + 2 * 52 - 6 } : { x: cfg.w - 12 - w, y: 90 };
    html += menu(p.x, p.y, w, secs).html;
  }
  if (o === 'delete') {
    const title = 'Delete this puzzle from the library?';
    const act = [{ label: 'Delete Puzzle', role: 'destructive' }];
    if (!g.compact) html += popover(sideX != null ? sideX : cfg.w - 34, sideX != null ? 186 + 2 * 52 + 22 : 60, sideX != null ? 'left' : 'below', title, null, act);
    else html += dim(cfg) + actionSheet(g.content.x0 + 8, g.content.x1 - g.content.x0 - 16, cfg.h - cfg.bottom - 4, title, null, act);
  }
  if (o === 'comment') {
    const body = `<div style="background:var(--bg2);border-radius:12px;padding:12px 14px;height:150px;font-size:17px;line-height:22px">${PZ.comment}<span class="caret" style="display:inline-block;width:2px;height:20px;background:var(--accent);vertical-align:-4px"></span></div><div style="color:var(--red);text-align:center;padding:14px;font-size:17px">Remove Comment</div>`;
    html += dim(cfg);
    if (g.compact) {
      // Phase 1: medium sheet 450 × 390, 8 pt from each edge, ✕ / ✓ in the side bar
      const y = cfg.h - 8 - 390;
      html += sheet(8, y, cfg.w - 16 - 76, 390, '#1', body, { sideControls: true, grabber: true });
      html += abs(cfg.w - cfg.side.w + 20, y + 10, 44, 44, icon('xmark', 19), 'tb', 'z-index:47') + abs(cfg.w - cfg.side.w + 20, y + 62, 44, 44, icon('check', 20), 'tb on', 'z-index:47');
    } else if (g.mode === 'pages') html += sheet(8, 40, 440, 330, '#1', body);
    else if (g.mode === 'halves') html += sheet((cfg.w - 653) / 2, 413.5 + 16, 653, 330, '#1', body);
    else { const w = 653; html += sheet((cfg.w - (cfg.side ? cfg.side.w : 0) - w) / 2, 60, w, 330, '#1', body); }
  }
  return html;
}

function wrap(html, g, st, id, k, opts, B, cfg) {
  const chips = [{ text: cfg.size }, { text: `bars: ${g.bars === 'side' ? cfg.bars + ' side bar' : 'top + bottom'}` }];
  const ct = st.kind === 'session' ? 'fullScreenCover › NavigationStack' : 'NavigationSplitView detail';
  chips.push({ text: `${ct} › AnyLayout(${g.mode === 'stack' || g.mode === 'halves' ? 'VStack' : 'HStack'})`, kind: 'ct' });
  if (B) {
    const sq = B / 8, ok = sq >= MIN_TARGET;
    chips.push({ text: `board ${B} pt · ${sq.toFixed(1)} pt squares`, kind: ok ? '' : 'exc' });
    if (!ok) chips.push({ text: g.compact ? '§6.6 exception: decision 5' : g.mode === 'halves' ? '§6.6 exception: decision 10' : '§6.6 exception: open', kind: 'exc' });
    chips.push({ text: 'board fits without scrolling', kind: 'fix' });
  }
  if (g.cover != null) chips.push({ text: g.cover > 0 ? `card covers ${Math.round(g.cover)} pt of the board` : 'card beside or below the board', kind: g.cover > 0 ? '' : 'fix' });
  if (g.clip) chips.push({ text: 'card scrolls' });
  if (g.listClipped) chips.push({ text: 'info list scrolls under a pinned board' });
  if (g.mode === 'pages') chips.push({ text: 'nothing on the division', kind: 'fix' });
  if (g.mode === 'halves') chips.push({ text: 'board above the division, controls below', kind: 'fix' });
  (opts.chips || []).forEach((c) => chips.push(c));
  const fid = opts.fid || `${id}·${k}`;
  return frame(fid, cfg === CFG.SVR ? 'SVR' : k === 'SV' ? 'SVL' : k === 'FTalt' ? 'FT' : k, html, chips, { caption: opts.caption || S[id].t, cls: (opts.rt ? 'rt ' : '') + (opts.ax5 ? 'ax5' : '') });
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
          out += compose(s.id, 'SV', { fid: `${s.id}·SV` + (s.id === 'S09a' ? ' (left)' : '') });
          if (s.id === 'S09a') out += compose(s.id, 'SVR', { geomKey: 'SVR', fid: 'S09a·SV (right)' });
        } else out += compose(s.id, col);
      } else out += `<div class="eqcell"><b>${s.id}·${col}</b>${p.eq ? '= ' + p.eq : 'n/a'}${p.why ? `<br><i>${p.why}</i>` : ''}</div>`;
    });
    out += '</div>';
  });
  return out;
}

function renderVariants() {
  let out = '<div class="state-row"><div class="state-label"><b>AX5</b>Dynamic Type AX5</div>';
  out += compose('S09a', 'O', { ax5: true, fid: 'S09a·O·AX5', caption: 'AX5' }) + compose('S09a', 'IL', { ax5: true, fid: 'S09a·IL·AX5', caption: 'AX5' });
  out += compose('S08a', 'O', { ax5: true, fid: 'S08a·O·AX5', caption: 'AX5' }) + compose('S08a', 'IL', { ax5: true, fid: 'S08a·IL·AX5', caption: 'AX5' });
  out += '</div><div class="state-row"><div class="state-label"><b>RT</b>Reduce Transparency</div>';
  out += compose('S09i', 'O', { rt: true, fid: 'S09i·O·RT', caption: 'Reduce Transparency' }) + compose('S09i', 'IL', { rt: true, fid: 'S09i·IL·RT', caption: 'Reduce Transparency' });
  out += compose('S08a', 'O', { rt: true, fid: 'S08a·O·RT', caption: 'Reduce Transparency' }) + compose('S08a', 'IL', { rt: true, fid: 'S08a·IL·RT', caption: 'Reduce Transparency' });
  return out + '</div>';
}

function renderStoryboards() {
  return `<h2>Unfold mid-session (S09a)</h2><div class="story">`
    + compose('S09a', 'O', { fid: '1 · closed', caption: 'Puzzle 3 of 6, your move' })
    + '<span class="arrow">→</span>'
    + compose('S09a', 'FB', { fid: '2 · opening (90°)', caption: 'Same SolveModel; board moves to the left page, prompt to the right' })
    + '<span class="arrow">→</span>'
    + compose('S09a', 'IL', { fid: '3 · open', caption: 'Same puzzle, same move; a drag in progress is cancelled, nothing is recorded' })
    + '</div>';
}

function renderCoverage() {
  let rows = '', drawn = 0, eq = 0;
  STATES.forEach((s) => {
    rows += `<tr><th style="text-align:left">${s.id} <span style="font-weight:400">${s.t}</span></th>`;
    COLS.forEach((col) => {
      const p = cellPlan(s.id, col);
      if (p.drawn) { drawn++; rows += `<td class="drawn"><a href="#${s.id}·${col}">●</a></td>`; } else { eq++; rows += `<td class="eq">= ${p.eq}</td>`; }
    });
    rows += '</tr>';
  });
  return `<p>${STATES.length} states × ${COLS.length} configurations = ${STATES.length * COLS.length} cells: <b>${drawn} drawn</b>, ${eq} equal to a drawn frame, 0 blank. Plus 8 system-variant frames, 3 storyboard frames and S09a on the right Split View half.</p><table class="cov"><tr><th></th>${COLS.map((c) => `<th>${c}</th>`).join('')}</tr>${rows}</table>`;
}
