// Sheets canvas (S05 Import puzzles, S13 Import PGN, S14 New Game, S16 Analysis sheets).
// Placement follows Phase 1 (§8.1): side ✕ / ✓ on O and SV; centered 653 pt with
// horizontal ✕ / ✓ on the inner display; the left page on FB; below the division on FT.

const COLS = ['O', 'IL', 'IP', 'SV', 'FB', 'FT', 'PP', 'PD'];

const STATES = [
  { id: 'S05a', t: 'Nothing yet', scr: 'imp' },
  { id: 'S05b', t: 'Parsed, existing collection', scr: 'imp', found: 'ok', dest: 'existing' },
  { id: 'S05c', t: 'Parsed, new collection', scr: 'imp', found: 'ok', dest: 'new' },
  { id: 'S05d', t: 'Rejected rows', scr: 'imp', found: 'some', dest: 'existing' },
  { id: 'S05e', t: 'All rows rejected', scr: 'imp', found: 'none' },
  { id: 'S05f', t: 'Several collections', scr: 'imp', found: 'groups' },
  { id: 'S05g', t: 'Source error', scr: 'imp', srcErr: true },
  { id: 'S05h', t: 'Busy', scr: 'imp', found: 'ok', dest: 'existing', busy: true },
  { id: 'S05i', t: 'Offline (F19)', scr: 'imp', found: 'ok', dest: 'existing', offline: true },
  { id: 'S05j', t: 'Keyboard in editor', scr: 'imp', typing: true, kb: true },
  { id: 'S05k', t: 'Files picker', scr: 'imp', files: true },
  { id: 'S05l', t: 'Opened from a collection (preselected)', scr: 'imp', found: 'ok', dest: 'existing', fromColl: true },
  { id: 'S13a', t: 'Nothing yet', scr: 'pgn' },
  { id: 'S13b', t: 'Games read', scr: 'pgn', found: 3 },
  { id: 'S13c', t: 'More than 5 games', scr: 'pgn', found: 12 },
  { id: 'S13d', t: 'Read errors', scr: 'pgn', found: 8, errors: true },
  { id: 'S13e', t: 'Source error', scr: 'pgn', srcErr: true },
  { id: 'S13f', t: 'Busy', scr: 'pgn', found: 3, busy: true },
  { id: 'S13g', t: 'Offline', scr: 'pgn', found: 3, offline: true },
  { id: 'S13h', t: 'Keyboard', scr: 'pgn', typing: true, kb: true },
  { id: 'S13i', t: 'Files picker', scr: 'pgn', files: true },
  { id: 'S14a', t: 'Standard start', scr: 'new' },
  { id: 'S14b', t: 'From FEN, empty', scr: 'new', fen: 'empty' },
  { id: 'S14c', t: 'Valid FEN', scr: 'new', fen: 'ok' },
  { id: 'S14d', t: 'Invalid FEN (board dimmed)', scr: 'new', fen: 'bad' },
  { id: 'S14e', t: 'Keyboard', scr: 'new', fen: 'ok', kb: true },
  { id: 'S14f', t: 'Offline (F19)', scr: 'new', offline: true },
  { id: 'S16a', t: 'Comment, empty', scr: 'comment' },
  { id: 'S16b', t: 'Comment with text (Remove Comment)', scr: 'comment', text: true },
  { id: 'S16c', t: 'Comment at large detent', scr: 'comment', text: true, large: true },
  { id: 'S16d', t: 'Comment, keyboard', scr: 'comment', text: true, kb: true },
  { id: 'S16e', t: 'Details', scr: 'details' },
  { id: 'S16f', t: 'Details, keyboard', scr: 'details', kb: true },
  { id: 'S16g', t: 'Share sheet (Export PGN)', scr: 'share' },
  { id: 'S16h', t: 'Game note', scr: 'comment', text: true, note: true },
];
const S = Object.fromEntries(STATES.map((s) => [s.id, s]));

const DRAW = {
  IP: ['S05a', 'S05j', 'S13b', 'S14a', 'S14e', 'S16a', 'S16e'],
  SV: ['S05a', 'S14a', 'S16a', 'S16d'],
  FB: ['S05a', 'S05j', 'S14a', 'S14e', 'S16a', 'S16d', 'S16g'],
  FT: ['S05a', 'S14a', 'S16a', 'S16d'],
  PD: ['S05a', 'S14a', 'S16a'],
};
const PRIM = { imp: 'S05a', pgn: 'S13a', new: 'S14a', comment: 'S16a', details: 'S16e', share: 'S16g' };

function cellPlan(id, col) {
  if (col === 'O' || col === 'IL') return { drawn: true };
  if ((DRAW[col] || []).includes(id)) return { drawn: true };
  const st = S[id], p = st.kb && st.scr === 'imp' ? 'S05j' : st.kb && st.scr === 'new' ? 'S14e' : st.kb && st.scr === 'comment' ? 'S16d' : PRIM[st.scr];
  const map = { imp: 'S05', pgn: 'S05', new: 'S14', comment: 'S16', details: 'S16', share: 'S16' };
  const prim = st.scr === 'pgn' ? (st.kb ? 'S05j' : 'S05a') : p;
  switch (col) {
    case 'IP': return { eq: `${prim}·IP + form of ${id}·IL`, why: 'compact width inside the sheet (§8.1)' };
    case 'SV': return { eq: `${id}·O`, why: 'compact width' };
    case 'FB': return { eq: `${prim}·FB + form of ${id}·IL`, why: 'sheet on the left page' };
    case 'FT': return { eq: `${prim === 'S05j' || prim === 'S14e' ? prim.replace(/.$/, 'a') : prim}·FT + form of ${id}·IP`, why: 'sheet below the division' };
    case 'PP': return { eq: `${id}·IL`, why: 'decision 9' };
    case 'PD': return { eq: `${id}·IL`, why: 'iPad = regular layouts (D11)' };
  }
}

// ---------- Host (dimmed, behind the sheet) ----------

function host(st, g, cfg) {
  let html = '';
  if (st.scr === 'comment' || st.scr === 'details' || st.scr === 'share') {
    const bg = boardGeom(g.k, {});
    if (bg.bars === 'side') html += sideBar(cfg, [{ icon: 'chevL' }, { icon: 'flip' }, { icon: 'lines' }, { icon: 'ellipsis' }], [{ icon: 'chevL', step: true }, { icon: 'chevR', step: true }]);
    else html += statusBar(cfg);
    html += abs(bg.evalX, bg.boardY, 14, bg.B, evalBar(bg.B, 0.54, '0.4'));
    html += abs(bg.boardX, bg.boardY, bg.B, bg.B, board(bg.B, { fen: 'r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4', hl: ['a7', 'a6'] }));
    html += abs(bg.col.x, bg.col.y, bg.col.w, bg.col.h, moveList(bg.col.w, bg.col.h, [{ n: 1, w: 'e4', b: 'e5' }, { n: 2, w: 'Nf3', b: 'Nc6' }, { n: 3, w: 'Bb5', b: 'a6', sel: 'b' }, { n: 4, w: 'Ba4', b: 'Nf6' }, { n: 5, w: 'O-O', b: 'Be7' }]).html);
    return html;
  }
  const games = st.scr !== 'imp';
  if (g.bars === 'side') html += sideBar(cfg, [{ icon: 'person', cls: 'avatar-tb' }, { icon: 'plus' }], []);
  else html += statusBar(cfg);
  const c0 = g.cols[0];
  html += abs(c0.x + 20, g.top + 14, c0.w - 40, 50, `<div class="ttl" style="font-size:34px;line-height:41px">${games ? 'Club games' : 'Puzzles'}</div>`);
  html += abs(c0.x + 16, g.top + 80, c0.w - 32, cfg.h - g.top - 80, games ? gamesList({}) : puzzlesList({}), 'listwrap', 'overflow:hidden');
  return html;
}

// ---------- Sheet placement (§8.1) ----------

function place(g, cfg, o) {
  const kbH = o.kb ? (g.compact ? 313 : 289) : 0;
  let p;
  if (g.compact) {
    const x = g.contentX0 + 8, w = g.contentX1 - g.contentX0 - 16;
    if (o.detent === 'medium' && !o.kb) p = { x, w, y: cfg.h - 8 - 390, h: 390 };
    else p = { x, w, y: o.kb ? 8 : 24, h: cfg.h - (o.kb ? 8 : 24) };
    p.side = true;
  } else if (g.k === 'FB') p = { x: 8, w: 447.5 - 8, y: o.kb ? 8 : 24, h: cfg.h - (o.kb ? 16 : 48) };
  else if (g.k === 'FT') p = { x: (cfg.w - 653) / 2, w: 653, y: 413.5 + 8, h: cfg.h - 413.5 - 16 };
  else {
    const w = g.k === 'PD' ? 580 : 653;
    const x = (cfg.w - (cfg.side ? cfg.side.w : 0) - w) / 2;
    if (o.detent === 'medium' && !o.kb && g.k !== 'IL') p = { x, w, y: cfg.h / 2 - 220, h: 440 };
    else p = { x, w, y: o.kb ? 8 : 24, h: cfg.h - (o.kb ? 16 : 48) };
  }
  p.kbH = kbH;
  p.visibleH = kbH ? Math.min(p.h, cfg.h - kbH - p.y) : p.h;
  return p;
}

function sheetFrame(g, cfg, p, title, body, o = {}) {
  let html = dim(cfg);
  const confirmCls = `tb on${o.confirmDisabled ? ' dis' : ''}`;
  const confirm = o.busy ? '<span class="spinner" style="border-top-color:#fff;border-color:rgba(255,255,255,.4)"></span>' : icon('check', 20);
  let head;
  if (p.side) head = `<div class="sh-head"><span class="sh-title">${title}</span></div>`;
  else head = `<div class="sh-head">${abs(12, 10, 44, 44, icon('xmark', 19), 'tb')}<span class="sh-title">${title}</span>${o.noConfirm ? '' : abs(p.w - 56, 10, 44, 44, confirm, confirmCls, o.confirmDisabled ? 'background:var(--fill2);color:var(--label3)' : '')}</div>`;
  html += abs(p.x, p.y, p.w, p.h, head + `<div class="sh-body" style="height:${p.visibleH - 64}px;overflow:hidden">${body}</div>`, 'sheet' + (p.side ? ' grab' : ''));
  if (p.side) {
    const bx = cfg.side.edge === 'R' ? cfg.w - cfg.side.w + 20 : 20;
    // below the status zone that the side bar shares with the camera and status bar
    const cy = Math.max(p.y + 10, 186);
    html += abs(bx, cy, 44, 44, icon('xmark', 19), 'tb', 'z-index:47');
    if (!o.noConfirm) html += abs(bx, cy + 52, 44, 44, confirm, confirmCls, `z-index:47;${o.confirmDisabled ? 'background:var(--fill2);color:var(--label3)' : ''}`);
  }
  if (p.kbH) {
    const kl = (t) => `<div style="padding:14px;color:var(--label2);font-size:13px;text-align:center">${t}</div>`;
    if (g.compact || g.k === 'IP' || g.k === 'FT') html += abs(0, cfg.h - p.kbH, cfg.w, p.kbH, kl(`Keyboard ${p.kbH} pt`), 'kbd');
    else html += abs(0, cfg.h - 289, 360, 289, kl('Split keyboard 289 pt'), 'kbd') + abs(cfg.w - 360, cfg.h - 289, 360, 289, kl('Split keyboard 289 pt'), 'kbd');
  }
  return html;
}

// ---------- Forms ----------

const lr = (inner, style = '') => `<div class="lrow" style="${style}">${inner}</div>`;
const accentRow = (ic, t, dis) => lr(`<span style="color:var(--accent);opacity:${dis ? 0.4 : 1};display:flex;gap:10px;align-items:center">${icon(ic, 19)}${t}</span>`);
const editor = (text, h, typing) => `<div class="lrow" style="align-items:flex-start;min-height:${h}px;font:13px/18px ui-monospace,'DejaVu Sans Mono',monospace;background:var(--bg2)">${text ? text : '<span style="color:var(--label3)">Paste here</span>'}${typing ? '<span class="caret" style="display:inline-block;width:2px;height:16px;background:var(--accent)"></span>' : ''}</div>`;
const offlineNote = (t) => `<div class="offnote">${icon('wifiSlash', 16)}<span>${t}</span></div>`;

function importBody(st, w) {
  let b = '';
  // F19: the offline reason sits at the top of the form, next to the disabled ✓, not below the fold
  if (st.offline) b += offlineNote(st.scr === 'imp' ? 'You’re offline. Importing needs a connection.' : 'You’re offline. Adding games needs a connection.');
  const pgn = st.scr === 'pgn';
  const src = st.typing ? (pgn ? '[Event "Club night"]<br>1. e4 e5 2. Nf3 Nc6 3. Bb5' : '{"name": "Back-rank mates",<br> "puzzles": [{"fen": "6k1/5ppp') : st.found || st.srcErr ? (pgn ? '[Event "Club championship"]<br>[White "Me"] …' : '{"name": "Tactics 2026", "puzzles": [ …') : '';
  const foot = st.srcErr ? `<span style="color:var(--red-text);display:flex;gap:6px">${icon('warn', 15)}${pgn ? 'This text has no PGN games.' : 'This isn’t a Motif collection file.'}</span>` : pgn ? 'PGN files, or their text pasted above.' : 'A JSON collection file, or its text pasted above.';
  b += section('Source', [accentRow('doc', pgn ? 'Choose Files…' : 'Choose File…'), accentRow('doc', 'Paste From Clipboard'), editor(src, 96, st.typing)], { footer: foot });
  if (!pgn && st.found) {
    const ok = (n) => lr(`<span style="color:var(--accent)">${icon('checkCircle', 20)}</span>${n} puzzles ready to add`);
    const rej = (n) => lr(`<span style="color:#ff9500">${icon('warn', 20)}</span>${n} rows rejected`);
    const rows = { ok: [ok(12)], some: [ok(10), rej(2), lr('<span style="color:var(--red-text);font-size:13px">Row 4: missing FEN<br>Row 9: illegal position (two white kings)</span>')], none: [rej(12), lr('<span style="color:var(--red-text);font-size:13px">Row 1: missing FEN · Row 2: missing FEN · …</span>')], groups: [ok(12), lr('Back rank<span class="lr-v" style="margin-left:auto">6 puzzles</span>'), lr('Forks<span class="lr-v" style="margin-left:auto">4 puzzles</span>'), lr('Pins<span class="lr-v" style="margin-left:auto">2 puzzles</span>')] }[st.found];
    b += section('Found', rows);
    if (st.found !== 'none') {
      if (st.found === 'groups') b += section('Add to', [lr('Collections<span class="lr-v" style="margin-left:auto">As named in the file</span>')], { footer: 'Creates Back rank, Forks and Pins.' });
      else b += section('Add to', [lr(`Collection<span class="lr-v" style="margin-left:auto;color:var(--accent)">${st.dest === 'new' ? 'New Collection' : 'Back-rank mates'} ⌄</span>`), ...(st.dest === 'new' ? [lr('Tactics 2026<span class="caret" style="display:inline-block;width:2px;height:20px;background:var(--accent)"></span>')] : [])], { footer: st.dest === 'new' ? 'Creates a collection with 12 puzzles.' : `Adds 12 puzzles to Back-rank mates${st.fromColl ? ' (opened from this collection).' : '.'}` });
    }
  }
  if (pgn && st.found) {
    const titles = ['Me – Club friend', 'Club friend – Me', 'Alpha – Beta', 'Me – Engine', 'Carlsen – Nakamura'].slice(0, Math.min(5, st.found));
    const rows = [lr(`${st.found} games read${st.errors ? ' · 2 couldn’t be read' : ''}`)];
    if (st.errors) rows.push(lr('<span style="color:var(--red-text);font-size:13px">Game 4: illegal move 17. Nxe5<br>Game 9: unclosed comment</span>'));
    titles.forEach((t) => rows.push(lr(t)));
    if (st.found > 5) rows.push(lr(`<span style="color:var(--label2)">and ${st.found - 5} more games</span>`));
    b += section('Found', rows);
  }
  return b;
}

function filesPicker(g, cfg, p) {
  const files = ['tactics-2026.json', 'back-rank.json', 'club-championship.pgn', 'endgames.json'];
  const body = `<div class="seg" style="margin:0 0 12px"><span class="on">Recents</span><span>Browse</span></div><div class="search" style="margin-bottom:12px">${icon('search', 17)}<span style="color:var(--label3)">Search</span></div>${section('', files.map((f) => row({ lead: `<span class="itile" style="background:var(--fill2);color:var(--label)">${icon('doc', 17)}</span>`, title: f, sub: 'iCloud Drive · Downloads' })))}`;
  const q = { ...p, y: p.y + 14, h: p.h - 14 };
  return dim(cfg) + abs(q.x, q.y, q.w, q.h, `<div class="sh-head"><span class="tb" style="position:absolute;left:12px;top:10px;width:auto;padding:0 14px;height:44px;border-radius:22px;color:var(--accent)">Cancel</span><span class="sh-title">Choose a File</span><span class="tb" style="position:absolute;right:12px;top:10px;width:auto;padding:0 14px;height:44px;border-radius:22px;color:var(--label3)">Open</span></div><div class="sh-body">${body}</div>`, 'sheet');
}

function newGameBody(st, g, p) {
  const fromFen = !!st.fen;
  const bad = st.fen === 'bad', empty = st.fen === 'empty';
  // F18: the preview board is capped so the FEN field and its error stay on screen.
  // Wide sheets (≥ 600 pt) put the board beside the form; narrow ones cap it at 40 % of the visible height.
  const wide = p.w >= 600 && g.k !== 'IP' && g.k !== 'FT'; // IP / FT sheets are compact width inside (§8.1)
  const avail = p.visibleH - 64 - 52;
  const B = wide ? Math.min(Math.floor((p.w - 32) * 0.45 / 8) * 8, Math.floor((avail - 20) / 8) * 8) : Math.min(Math.floor((p.w - 32) / 8) * 8, Math.floor(avail * 0.4 / 8) * 8);
  const fen = empty ? '' : bad ? '8/8/8/4k3/8/8/8/8 w - - 0 1 x' : fromFen ? '6k1/5ppp/8/8/8/8/5PPP/R3R1K1 w - - 0 1' : '';
  const brd = `<div style="display:flex;justify-content:center">${board(B, { fen: fromFen && !empty ? (bad ? '8/8/8/4k3/8/8/8/8 w - - 0 1' : fen) : fromFen ? '8/8/8/8/8/8/8/8 w - - 0 1' : START_FEN, dim: bad || empty })}</div>`;
  let form = '';
  if (st.offline) form += offlineNote('You’re offline. Adding games needs a connection.');
  form += `<div class="seg" style="margin:4px 0 12px"><span class="${fromFen ? '' : 'on'}">Standard Start</span><span class="${fromFen ? 'on' : ''}">From a FEN</span></div>`;
  if (fromFen) form += section('Starting Position', [`<div class="lrow" style="font:13px/18px ui-monospace,'DejaVu Sans Mono',monospace;background:var(--bg2);min-height:64px;align-items:flex-start">${fen || '<span style="color:var(--label3)">FEN</span>'}${st.kb ? '<span class="caret" style="display:inline-block;width:2px;height:16px;background:var(--accent)"></span>' : ''}</div>`], { footer: bad ? `<span style="color:var(--red-text);display:flex;gap:6px">${icon('warn', 15)}Invalid FEN: the side to move is missing a king.</span>` : empty ? 'Paste or type a FEN.' : 'White to move. The board faces the side to move.' });
  else form += `<div class="sec-f">White to move. The board faces the side to move.</div>`;
  if (wide) return { body: `<div style="display:flex;gap:16px;align-items:flex-start"><div style="flex:none">${brd}</div><div style="flex:1;min-width:0">${form}</div></div>`, B, wide };
  return { body: `${form.includes('seg') ? form.slice(0, form.indexOf('</div>', form.indexOf('class="seg"')) + 6) : ''}${brd}<div style="height:12px"></div>${form.slice(form.indexOf('</div>', form.indexOf('class="seg"')) + 6)}`, B, wide };
}

function commentBody(st, p) {
  const text = st.text ? (st.note ? 'Played in the last round. Prepared 6. Re1 but forgot the b5 move order.' : 'The Morphy Defence. 4. Bxc6 gives up the bishop pair for a better pawn structure.') : '';
  const h = st.large ? 260 : 150;
  // F20: solid editor background, nothing shows through
  let b = section(st.note ? 'Me – Club friend' : '3… a6', [`<div class="lrow" style="align-items:flex-start;min-height:${h}px;background:var(--bg2)">${text || '<span style="color:var(--label3)">Comment</span>'}${st.kb ? '<span class="caret" style="display:inline-block;width:2px;height:20px;background:var(--accent);vertical-align:-4px"></span>' : ''}</div>`]);
  if (st.text) b += `<div style="color:var(--red);text-align:center;padding:14px;font-size:17px">Remove Comment</div>`;
  return b;
}

function detailsBody(st) {
  const f = (l, v, ph) => lr(`<span>${l}</span><span style="margin-left:auto;color:${v ? 'var(--label)' : 'var(--label3)'}">${v || ph}</span>`);
  return section('Players', [f('White', 'Me'), f('Rating', '', 'Unrated'), f('Black', 'Club friend'), f('Rating', '1650')])
    + section('Result', [`<div class="lrow"><div class="seg" style="flex:1"><span class="on">1-0</span><span>½-½</span><span>0-1</span><span>*</span></div></div>`])
    + section('Event', [f('Event', 'Club championship'), f('Site', '', 'Unknown'), f('Date', '2026.10.12'), f('Round', '4')])
    + section('Opening', [f('Opening', 'Ruy Lopez'), f('ECO', 'C78')]);
}

// ---------- Composer ----------

function compose(id, k, opts = {}) {
  const st = { ...S[id], ...(opts.st || {}) };
  const gk = opts.geomKey || (k === 'SV' ? 'SVL' : k);
  const cfg = CFG[gk];
  const g = shellGeom(gk);
  let html = host(st, g, cfg);
  const chips = [{ text: cfg.size }];
  let p;
  if (st.scr === 'imp' || st.scr === 'pgn') {
    p = place(g, cfg, { detent: 'large', kb: st.kb });
    const n = st.scr === 'imp' ? (st.found && st.found !== 'none' ? (st.found === 'some' ? 10 : 12) : 0) : st.found || 0;
    const disabled = !n || st.offline;
    html += sheetFrame(g, cfg, p, st.scr === 'imp' ? 'Import Puzzles' : 'Import PGN', importBody(st, p.w), { confirmDisabled: disabled, busy: st.busy });
    chips.push({ text: `✓ "${n ? `Add ${n} ${st.scr === 'imp' ? 'Puzzles' : 'Games'}` : 'Add'}"${disabled ? ' (disabled)' : ''}`, kind: 'ct' });
    if (st.files) html += filesPicker(g, cfg, p);
  } else if (st.scr === 'new') {
    p = place(g, cfg, { detent: 'large', kb: st.kb });
    const ng = newGameBody(st, g, p);
    html += sheetFrame(g, cfg, p, 'New Game', ng.body, { confirmDisabled: st.fen === 'bad' || st.fen === 'empty' || st.offline });
    chips.push({ text: `preview ${ng.B} pt${ng.wide ? ', beside the form' : ', capped at 40 % of the sheet'}`, kind: 'fix' });
  } else if (st.scr === 'comment') {
    p = place(g, cfg, { detent: st.large ? 'large' : 'medium', kb: st.kb });
    html += sheetFrame(g, cfg, p, st.note ? 'Game Note' : 'Comment', commentBody(st, p));
    chips.push({ text: `presentationDetents([.medium, .large]) · ${st.large ? 'large' : 'medium'}`, kind: 'ct' });
    if (g.compact && !st.large && !st.kb) chips.push({ text: 'covers the lower board (F29, accepted)' });
  } else if (st.scr === 'details') {
    p = place(g, cfg, { detent: 'large', kb: st.kb });
    html += sheetFrame(g, cfg, p, 'Details', detailsBody(st));
  } else if (st.scr === 'share') {
    // system activity view: sheet on compact, popover from the overflow item on regular
    const apps = ['Messages', 'Mail', 'Files', 'Notes'].map((a) => `<span class="shapp"><span></span>${a}</span>`).join('');
    const body = `<div style="padding:16px"><div style="display:flex;gap:12px;align-items:center;padding-bottom:14px"><span class="itile" style="width:44px;height:44px;background:var(--fill2);color:var(--label)">${icon('doc', 22)}</span><span style="display:flex;flex-direction:column"><b>Me – Club friend.pgn</b><span class="lr-s">PGN</span></span></div><div style="display:flex;gap:14px">${apps}</div><div class="glist" style="margin-top:14px"><div class="gl-row">Copy</div><div class="gl-row">Save to Files</div></div></div>`;
    if (g.compact) html += dim(cfg) + abs(g.contentX0 + 8, cfg.h - 8 - 330, g.contentX1 - g.contentX0 - 16, 330, body, 'sheet');
    else if (g.k === 'FB') html += dim(cfg) + abs(8, 120, 440, 310, body, 'sheet');
    else { const ax = cfg.side ? cfg.w - cfg.side.w : cfg.w - 34, ay = cfg.side ? 186 + 3 * 52 + 22 : 70; html += abs(cfg.side ? ax - 354 : ax - 330, cfg.side ? ay - 40 : ay + 14, 340, 310, `<span class="pop-arrow" style="${cfg.side ? 'right:-7px;top:33px' : 'top:-7px;right:20px'}"></span>${body}`, 'glass popover'); }
    chips.push({ text: g.compact ? 'activity view sheet' : g.k === 'FB' ? 'activity view on the left page' : 'activity view popover from the overflow item', kind: 'ct' });
  }
  if (p) chips.push({ text: p.side ? `sheet ${Math.round(p.w)} pt · ✕ / ✓ in the side bar` : g.k === 'FB' ? 'sheet on the left page' : g.k === 'FT' ? 'sheet below the division' : `form sheet ${p.w} pt, centered`, kind: g.k === 'FB' || g.k === 'FT' ? 'fix' : '' });
  if (p && p.kbH) chips.push({ text: `keyboard ${p.kbH} pt; ${Math.round(p.visibleH - 64)} pt of form visible` });
  (opts.chips || []).forEach((c) => chips.push(c));
  return frame(opts.fid || `${id}·${k}`, gk, html, chips, { caption: opts.caption || st.t, cls: (opts.rt ? 'rt ' : '') + (opts.ax5 ? 'ax5' : '') });
}

// ---------- Page ----------

function renderCanvas(prefix) {
  let out = '';
  STATES.filter((s) => s.id.startsWith(prefix)).forEach((s) => {
    out += `<div class="state-row"><div class="state-label"><b>${s.id}</b>${s.t}</div>`;
    COLS.forEach((col) => {
      const p = cellPlan(s.id, col);
      if (p.drawn) { out += compose(s.id, col, col === 'SV' && s.id === 'S16d' ? { geomKey: 'SVL', fid: 'S16d·SV' } : {}); }
      else out += `<div class="eqcell"><b>${s.id}·${col}</b>= ${p.eq}${p.why ? `<br><i>${p.why}</i>` : ''}</div>`;
    });
    out += '</div>';
  });
  return out;
}

function renderVariants() {
  const prim = ['S05a', 'S13a', 'S14a', 'S16a'];
  let out = '<div class="state-row"><div class="state-label"><b>AX5</b>Dynamic Type AX5</div>';
  prim.forEach((p) => { out += compose(p, 'O', { ax5: true, fid: `${p}·O·AX5`, caption: 'AX5' }) + compose(p, 'IL', { ax5: true, fid: `${p}·IL·AX5`, caption: 'AX5' }); });
  out += '</div><div class="state-row"><div class="state-label"><b>RT</b>Reduce Transparency</div>';
  prim.forEach((p) => { out += compose(p, 'O', { rt: true, fid: `${p}·O·RT`, caption: 'Reduce Transparency' }) + compose(p, 'IL', { rt: true, fid: `${p}·IL·RT`, caption: 'Reduce Transparency' }); });
  return out + '</div>';
}

function renderStoryboards() {
  return `<h2>Fold with a sheet and the keyboard open (S05j)</h2><div class="story">`
    + compose('S05j', 'IL', { fid: '1 · open', caption: 'Import Puzzles, typing in the editor; split keyboard' })
    + '<span class="arrow">→</span>'
    + compose('S05j', 'FB', { fid: '2 · folding (90°)', caption: 'Sheet slides onto the left page; keyboard session and draft text kept' })
    + '<span class="arrow">→</span>'
    + compose('S05j', 'O', { fid: '3 · closed', caption: 'Sheet at full height with ✕ / ✓ in the side bar; caret and text unchanged, keyboard stays up' })
    + '</div>';
}

function renderCoverage() {
  let rows = '', drawn = 0, eq = 0;
  STATES.forEach((s) => {
    rows += `<tr><th style="text-align:left">${s.id} <span style="font-weight:400">${s.t}</span></th>`;
    COLS.forEach((col) => { const p = cellPlan(s.id, col); if (p.drawn) { drawn++; rows += `<td class="drawn"><a href="#${s.id}·${col}">●</a></td>`; } else { eq++; rows += `<td class="eq">= ${p.eq}</td>`; } });
    rows += '</tr>';
  });
  return `<p>${STATES.length} states × ${COLS.length} configurations = ${STATES.length * COLS.length} cells: <b>${drawn} drawn</b>, ${eq} equal to a drawn frame, 0 blank. Plus 16 system-variant frames and 3 storyboard frames. S03 (Account) is on the Shell canvas and S10d/e (Save as Game) on the Analysis canvas.</p><table class="cov"><tr><th></th>${COLS.map((c) => `<th>${c}</th>`).join('')}</tr>${rows}</table>`;
}
