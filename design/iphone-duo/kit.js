// Shared component set for the iPhone Duo mockup canvases (plan §5.1).
// Every frame is generated from data: configurations below come from the
// Phase 1 measurements (§8.1), so changing a number here changes every frame.
// Units are points, drawn 1:1.

const CFG = {
  O:   { name: 'Closed', w: 466, h: 678, size: 'C × R', bars: 'trailing', side: { edge: 'R', w: 84 }, top: 0, bottom: 34, corner: 44, camera: { x: 399.7, y: 29.3, d: 37 } },
  IL:  { name: 'Open, wide', w: 951, h: 669, size: 'R × R', bars: 'trailing', side: { edge: 'R', w: 84 }, top: 0, bottom: 34, corner: 30, fold: { axis: 'x', at: 455.5, len: 40, active: false } },
  IP:  { name: 'Open, tall', w: 669, h: 951, size: 'R × R', bars: 'top + bottom', top: 82, bottom: 34, corner: 30, fold: { axis: 'y', at: 373.5, len: 40, active: false } },
  SVL: { name: 'Split View, left', w: 469, h: 669, size: 'C × R', bars: 'leading', side: { edge: 'L', w: 84 }, top: 0, bottom: 34, corner: 30, fold: { axis: 'x', at: 455.5, len: 13.5, active: true } },
  SVR: { name: 'Split View, right', w: 469, h: 669, size: 'C × R', bars: 'trailing', side: { edge: 'R', w: 84 }, top: 0, bottom: 34, corner: 30, fold: { axis: 'x', at: 0, len: 13.5, active: true } },
  FB:  { name: 'Folded, book', w: 951, h: 669, size: 'R × R + division', bars: 'trailing', side: { edge: 'R', w: 84 }, top: 0, bottom: 34, corner: 30, fold: { axis: 'x', at: 455.5, len: 40, active: true } },
  FT:  { name: 'Folded, tabletop', w: 669, h: 951, size: 'R × R + division', bars: 'top + bottom', top: 82, bottom: 34, corner: 30, fold: { axis: 'y', at: 373.5, len: 40, active: true } },
  PD:  { name: 'iPad 11″, landscape', w: 1194, h: 834, size: 'R × R', bars: 'top + bottom', top: 74, bottom: 20, corner: 18 },
};

const MIN_TARGET = 44;

const ICONS = {
  chevL: '<path d="M15 4l-8 8 8 8"/>',
  chevR: '<path d="M9 4l8 8-8 8"/>',
  ellipsis: '<circle cx="5" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.7" fill="currentColor" stroke="none"/>',
  flip: '<path d="M7 20V4M3.5 7.5L7 4l3.5 3.5M17 4v16M13.5 16.5L17 20l3.5-3.5"/>',
  lines: '<path d="M9 6h11M13 12h7M13 18h7"/><circle cx="4.5" cy="6" r="1.3" fill="currentColor" stroke="none"/><circle cx="8.5" cy="12" r="1.3" fill="currentColor" stroke="none"/><circle cx="8.5" cy="18" r="1.3" fill="currentColor" stroke="none"/>',
  xmark: '<path d="M6 6l12 12M18 6L6 18"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  trash: '<path d="M4 7h16M9 7V4.5h6V7M6.5 7l1 13h9l1-13M10 11v6M14 11v6"/>',
  pencil: '<path d="M4 20l1-4L16 5l3 3L8 19z"/>',
  bubble: '<path d="M4 5h16v11H10l-4 4v-4H4z"/>',
  doc: '<path d="M8 8h11v12H8zM5 16V4h11"/>',
  share: '<path d="M12 3v12M8 7l4-4 4 4M5 11v9h14v-9"/>',
  save: '<path d="M12 4v11M8 11l4 4 4-4M5 15v5h14v-5"/>',
  eyeSlash: '<path d="M3 12s3.5-6 9-6 9 6 9 6-3.5 6-9 6-9-6-9-6z"/><circle cx="12" cy="12" r="2.5"/><path d="M4 4l16 16"/>',
  chart: '<path d="M5 20V10M10 20V4M15 20v-7M20 20v-4"/>',
  wifiSlash: '<path d="M2.5 9a14 14 0 0119 0M5.5 12.5a9.5 9.5 0 0113 0M8.5 16a5 5 0 017 0M3 3l18 18"/>',
  wifi: '<path d="M2.5 9a14 14 0 0119 0M5.5 12.5a9.5 9.5 0 0113 0M8.5 16a5 5 0 017 0"/><circle cx="12" cy="19" r="1" fill="currentColor"/>',
  mainLine: '<path d="M5 4h14M12 20V8M7.5 12.5L12 8l4.5 4.5"/>',
  warn: '<path d="M12 3L2 20h20zM12 9v5"/><circle cx="12" cy="17" r=".8" fill="currentColor"/>',
  puzzle: '<path d="M4 8h4a2 2 0 114 0h4v4a2 2 0 110 4v4H4v-4a2 2 0 100-4z"/>',
  board: '<path d="M4 4h16v16H4zM4 12h16M12 4v16"/><path d="M4 4h8v8H4zM12 12h8v8h-8z" fill="currentColor" stroke="none" opacity=".35"/>',
  person: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6.5 18c1.5-2.5 3.5-3 5.5-3s4 .5 5.5 3"/>',
  folder: '<path d="M3 6.5h6.5l2 2H21V19H3z"/>',
  flag: '<path d="M6 21V4M6 4h11l-2.5 4L17 12H6"/>',
  flagFill: '<path d="M6 21V4M6 4h11l-2.5 4L17 12H6z" fill="currentColor"/>',
  skip: '<path d="M4 6l7 6-7 6zM12 6l7 6-7 6z" fill="currentColor"/>',
  toStart: '<path d="M6 5v14M19 5l-9 7 9 7z" fill="currentColor"/>',
  toEnd: '<path d="M18 5v14M5 5l9 7-9 7z" fill="currentColor"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5L20 20"/>',
  checkCircle: '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M7 12.5l3.5 3.5L17 9" stroke="#fff"/>',
  xCircle: '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M8.5 8.5l7 7M15.5 8.5l-7 7" stroke="#fff"/>',
  sparkle: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5L18 18M6 18l2.5-2.5M15.5 8.5L18 6"/>',
};

const icon = (n, s = 20, sw = 2.1) =>
  `<svg class="ic" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round">${ICONS[n] || ''}</svg>`;

const abs = (x, y, w, h, inner = '', cls = '', style = '') =>
  `<div class="${cls}" style="position:absolute;left:${x}px;top:${y}px;${w != null ? `width:${w}px;` : ''}${h != null ? `height:${h}px;` : ''}${style}">${inner}</div>`;

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

// ---------- Board ----------

const PIECE = { k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟' };

function parseFen(fen) {
  const rows = fen.split(' ')[0].split('/');
  const sq = {};
  rows.forEach((row, r) => {
    let f = 0;
    for (const c of row) {
      if (/\d/.test(c)) f += +c;
      else { sq['abcdefgh'[f] + (8 - r)] = c; f++; }
    }
  });
  return sq;
}

// opts: fen, hl (squares), flipped, dim, ghost {sq, piece}, mark {sq, label}, coords
function board(size, opts = {}) {
  const s = size / 8;
  const pos = parseFen(opts.fen || START_FEN);
  const hl = new Set(opts.hl || []);
  let html = '';
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const file = opts.flipped ? 7 - f : f;
      const rank = opts.flipped ? r + 1 : 8 - r;
      const name = 'abcdefgh'[file] + rank;
      const light = (file + rank) % 2 === 1;
      let bg = light ? 'var(--sq-light)' : 'var(--sq-dark)';
      if (hl.has(name)) bg = opts.hint ? (light ? 'var(--sq-hint-light)' : 'var(--sq-hint-dark)') : light ? 'var(--sq-hl-light)' : 'var(--sq-hl-dark)';
      if (opts.select === name) bg = 'var(--sq-sel)';
      let inner = '';
      const p = pos[name];
      if (p) {
        const white = p === p.toUpperCase();
        inner += `<span class="pc ${white ? 'w' : 'b'}" style="font-size:${s * 0.82}px;line-height:${s}px">${PIECE[p.toLowerCase()]}&#xFE0E;</span>`;
      }
      if (opts.ghost && opts.ghost.sq === name) inner += `<span class="pc w ghost" style="font-size:${s * 0.82}px;line-height:${s}px">${PIECE[opts.ghost.piece]}&#xFE0E;</span>`;
      if (opts.mark && opts.mark.sq === name) inner += `<span class="mark" style="width:${s * 0.36}px;height:${s * 0.36}px;font-size:${s * 0.22}px">${opts.mark.label}</span>`;
      const cc = light ? 'var(--sq-dark)' : 'var(--sq-light)';
      if (f === 0) inner += `<span class="coord rk" style="color:${cc};font-size:${Math.max(8, s * 0.2)}px">${rank}</span>`;
      if (r === 7) inner += `<span class="coord fl" style="color:${cc};font-size:${Math.max(8, s * 0.2)}px">${'abcdefgh'[file]}</span>`;
      html += `<div class="sq${(opts.flash || []).includes(name) ? ' flash' : ''}" style="left:${f * s}px;top:${r * s}px;width:${s}px;height:${s}px;background:${bg}">${inner}</div>`;
    }
  }
  return `<div class="board${opts.dim ? ' dim' : ''}" style="width:${size}px;height:${size}px">${html}</div>`;
}

function evalBar(h, whiteFrac, label, flipped) {
  const dark = (1 - whiteFrac) * h;
  return `<div class="evalbar" style="height:${h}px"><div class="evdark" style="height:${dark}px${flipped ? ';top:auto;bottom:0' : ''}"></div><span class="evlabel">${label}</span></div>`;
}

// ---------- Content blocks: each returns { html, h } at a given width ----------

function linesPanel(w, lines, o = {}) {
  const rowH = o.rowH || 34, head = o.head || 30;
  let html = `<div class="lp-head" style="height:${head}px"><span>ENGINE LINES</span><span>${o.starting ? '' : 'Depth 22'}</span></div>`;
  if (o.starting) {
    html += `<div class="lp-start" style="height:${rowH * (o.rows || 3)}px"><span class="spinner"></span>Starting engine…</div>`;
  } else {
    lines.slice(0, o.rows || 3).forEach((l) => {
      html += `<div class="lp-row" style="height:${rowH}px"><span class="lp-ev">${l.ev}</span><span class="lp-pv">${l.pv}</span></div>`;
    });
  }
  const h = head + rowH * (o.rows || 3) + 10;
  return { html: `<div class="panel lp" style="width:${w}px;height:${h}px">${html}</div>`, h };
}

function commentCard(w, text, maxLines = 3, fs = 15) {
  const lh = fs * 1.33;
  const charsPerLine = Math.max(10, Math.floor((w - 28) / (fs * 0.52)));
  const lines = Math.min(maxLines, Math.ceil(text.length / charsPerLine));
  const h = lines * lh + 24;
  const one = maxLines === 1 ? 'display:block;white-space:nowrap;text-overflow:ellipsis;' : '';
  return { html: `<div class="glass card cm" style="${one}width:${w}px;height:${h}px;font-size:${fs}px;line-height:${lh}px;-webkit-line-clamp:${maxLines}">${esc(text)}</div>`, h };
}

function altChips(w, items, expanded, fs = 15, single = false) {
  // single: one horizontally scrolling row with no header (compact width with little height)
  // Chips are 44 pt tall (fixes F9 for alternatives) and wrap inside the column, never over the board (F8).
  const shown = expanded ? items : items.slice(0, 3);
  const chips = shown.map((a, i) => `<span class="chip${i === 0 ? ' on' : ''}" style="font-size:${fs}px">${i === 0 ? icon('check', 14, 3) : ''}${a}</span>`);
  if (!expanded && items.length > 3) chips.push(`<span class="chip more" style="font-size:${fs - 2}px">+${items.length - 3} more ⌄</span>`);
  if (expanded) chips.push(`<span class="chip more" style="font-size:${fs - 2}px">Less ⌃</span>`);
  // estimate wrapping
  let rows = 1, x = 0;
  chips.forEach((c, i) => { const cw = (shown[i] || '+2 more').length * fs * 0.6 + 36; if (x + cw > w) { rows++; x = 0; } x += cw + 8; });
  if (single) return { html: `<div class="alts" style="width:${w}px;height:44px"><div class="alts-row single" aria-label="Alternatives">${chips.join('')}</div></div>`, h: 44 };
  const h = 18 + rows * 44 + (rows - 1) * 8;
  return { html: `<div class="alts" style="width:${w}px;height:${h}px"><div class="alts-h">ALTERNATIVES</div><div class="alts-row">${chips.join('')}</div></div>`, h };
}

// rows: [{n, w, b, sel: 'w'|'b', vari: true, text}]
function moveList(w, h, rows, o = {}) {
  const rowH = o.rowH || 34, fs = o.fs || 17;
  const fit = Math.max(0, Math.floor(h / rowH));
  let html = '';
  rows.slice(o.offset || 0, (o.offset || 0) + fit).forEach((r) => {
    if (r.vari) {
      html += `<div class="ml-row vari" style="height:${rowH}px;font-size:${fs - 2}px">${r.text}</div>`;
    } else {
      const ww = r.w ? `<span class="ml-m${r.sel === 'w' ? ' sel' : ''}${r.ctx === 'w' ? ' ctx' : ''}">${r.w}</span>` : '<span class="ml-m"></span>';
      const bb = r.b ? `<span class="ml-m${r.sel === 'b' ? ' sel' : ''}${r.ctx === 'b' ? ' ctx' : ''}">${r.b}</span>` : '';
      html += `<div class="ml-row" style="height:${rowH}px;font-size:${fs}px"><span class="ml-n">${r.n}.</span>${ww}${bb}</div>`;
    }
  });
  if (o.empty) html = `<div class="ml-empty">${o.empty}</div>`;
  return { html: `<div class="ml" style="width:${w}px;height:${h}px">${html}</div>`, h, fit };
}

function banner(kind, text) {
  const ic = kind === 'offline' ? 'wifiSlash' : kind === 'error' ? 'warn' : kind === 'toast' ? 'check' : 'sparkle';
  return `<span class="banner ${kind}">${icon(ic, 15)}${text}</span>`;
}

// ---------- Bars ----------

// Vertical side bar (system). items: [{icon, on, label, tint, disabled, group}]
function sideBar(cfg, top, bottom, o = {}) {
  const sw = cfg.side.w, x = cfg.side.edge === 'R' ? cfg.w - sw : 0;
  const bottomY = cfg.h - cfg.bottom;
  let html = '';
  // status zone (shared with the status bar and the camera)
  html += abs(0, 0, sw, 174, `<div class="sb-time">9:41</div><div class="sb-wifi">${icon('wifi', 22)}</div>`, 'sb-status', cfg.camera ? 'padding-top:72px' : 'padding-top:30px');
  let y = 186;
  top.forEach((it) => { html += sideItem(sw, y, it); y += 52; });
  if (o.topEnd) o.topEnd.y = y;
  if (bottom.length && bottom.every((i) => i.step)) html += stepPill(sw, bottomY - 46 * bottom.length, bottom, 'v');
  else { let by = bottomY - 44; [...bottom].reverse().forEach((it) => { html += sideItem(sw, by, it); by -= 52; }); }
  return abs(x, 0, sw, cfg.h, html, 'sidebar');
}

// Previous / Next Move: one ToolbarItemGroup, drawn as a grouped glass pill
function stepPill(sw, y, items, dir) {
  const inner = items.map((it) => `<span class="sp-btn ${it.disabled ? 'dis' : ''}">${icon(it.icon, 21)}</span>`).join(dir === 'v' ? '<span class="sp-sep v"></span>' : '<span class="sp-sep h"></span>');
  const n = items.length;
  return dir === 'v' ? abs((sw - 46) / 2, y, 46, 46 * n, inner, 'steppill v') : abs(sw, y, 50 * n, 46, inner, 'steppill h');
}

function sideItem(sw, y, it) {
  const cls = `tb ${it.on ? 'on' : ''} ${it.disabled ? 'dis' : ''} ${it.step ? 'step' : ''} ${it.cls || ''}`;
  return abs((sw - 44) / 2, y, 44, 44, ((it.cls || '').includes('avatar-tb') ? '<span class="avatar">S</span>' : icon(it.icon, 21)) + (it.label ? `<span class="tb-tip">${it.label}</span>` : ''), cls);
}

function navBar(cfg, y, left, title, right, o = {}) {
  const w = cfg.w;
  let html = '';
  if (left) html += abs(12, 0, 44, 44, icon(left.icon, 21), 'tb');
  html += `<div class="nb-title">${title}</div>`;
  let x = w - 12 - 44;
  [...right].reverse().forEach((it) => { html += abs(x, 0, 44, 44, icon(it.icon, 21), `tb ${it.on ? 'on' : ''} ${it.disabled ? 'dis' : ''} ${it.cls || ''}`); x -= 50; });
  return abs(0, y, w, 44, html, 'navbar', o.style || '');
}

function bottomBar(cfg, y, items, o = {}) {
  if (items.every((i) => i.step)) return abs(0, y, cfg.w, 46, stepPill((cfg.w - 50 * items.length) / 2, 0, items, 'h'), 'bottombar');
  if (items.length === 1 && items[0].text) return abs(0, y, cfg.w, 46, `<span class="glass capbtn">${icon(items[0].icon, 17)}${items[0].text}</span>`, 'bottombar', 'display:flex;justify-content:center');
  const totalW = items.length * 50 - 6;
  let x = (cfg.w - totalW) / 2;
  if (o.x != null) x = o.x;
  let html = '';
  items.forEach((it) => { html += abs(x - (o.x != null ? o.x : 0), 0, 44, 44, icon(it.icon, 21), `tb ${it.on ? 'on' : ''} ${it.disabled ? 'dis' : ''} ${it.step ? 'step' : ''}`); x += 50; });
  return abs(o.x != null ? o.x : 0, y, o.x != null ? totalW : cfg.w, 44, html, 'bottombar');
}

function statusBar(cfg) {
  const island = abs(cfg.w / 2 - 55, 9, 110, 30, '', 'island');
  return abs(0, 0, cfg.w, 50, `<span class="st-time">9:41</span>${island}<span class="st-icons">${icon('wifi', 17)}<span class="batt"></span></span>`, 'statusbar');
}

function tabBar(cfg, sel) {
  // used by list canvases later
  return '';
}

// ---------- Device chrome ----------

function chrome(cfg, o = {}) {
  let html = '';
  if (cfg.camera) html += abs(cfg.camera.x, cfg.camera.y, cfg.camera.d, cfg.camera.d, '', 'camera');
  if (cfg.fold) {
    const f = cfg.fold;
    if (f.axis === 'x') {
      if (f.active) html += abs(f.at, 0, f.len, cfg.h, '', 'division');
      else html += abs(f.at + f.len / 2, 0, 0, cfg.h, '', 'foldline v');
    } else {
      if (f.active) html += abs(0, f.at, cfg.w, f.len, '', 'division');
      else html += abs(0, f.at + f.len / 2, cfg.w, 0, '', 'foldline h');
    }
  }
  // home indicator
  const hx = cfg.side && cfg.side.edge === 'R' ? (cfg.w - cfg.side.w) / 2 : cfg.side ? cfg.side.w + (cfg.w - cfg.side.w) / 2 : cfg.w / 2;
  html += abs(hx - 67, cfg.h - 9, 134, 5, '', 'homeind');
  return html;
}

// ---------- Overlays ----------

// sections: [[{label, icon, role, sub, disabled}]]
function menu(x, y, w, sections, o = {}) {
  let html = '';
  let h = 0;
  sections.forEach((sec, si) => {
    if (si) { html += '<div class="mn-sep"></div>'; h += 8; }
    sec.forEach((it) => {
      html += `<div class="mn-row ${it.role || ''} ${it.disabled ? 'dis' : ''}" style="height:${it.sub ? 56 : 44}px"><span><span>${it.label}</span>${it.sub ? `<span class="mn-sub">${it.sub}</span>` : ''}</span>${it.icon ? icon(it.icon, 18) : ''}</div>`;
      h += it.sub ? 56 : 44;
    });
  });
  if (o.title) { html = `<div class="mn-title">${o.title}</div>` + html; h += 34; }
  return { html: abs(x, y, w, h + 12, html, 'glass menu'), h: h + 12 };
}

function dim(cfg) { return abs(0, 0, cfg.w, cfg.h, '', 'dimmer'); }

// compact confirmationDialog: action sheet at the bottom of the container
function actionSheet(x, w, bottomY, title, msg, actions) {
  const headH = msg ? 64 : 44;
  const h1 = headH + actions.length * 57;
  let html = abs(x, bottomY - 57 - 8 - h1, w, h1,
    `<div class="as-head"><b>${title}</b>${msg ? `<span>${msg}</span>` : ''}</div>` + actions.map((a) => `<div class="as-btn ${a.role || ''}">${a.label}</div>`).join(''), 'glass actionsheet');
  html += abs(x, bottomY - 57, w, 57, '<div class="as-btn cancel">Cancel</div>', 'glass actionsheet');
  return html;
}

// regular confirmationDialog: popover anchored to the control that asked
function popover(ax, ay, side, title, msg, actions) {
  const w = 280;
  const h = (msg ? 70 : 46) + actions.length * 50;
  let x = side === 'left' ? ax - w - 14 : side === 'right' ? ax + 14 : ax - w / 2;
  let y = side === 'below' ? ay + 14 : side === 'above' ? ay - h - 14 : ay - h / 2;
  const arrow = side === 'left' ? `right:-7px;top:${ay - y - 7}px` : side === 'right' ? `left:-7px;top:${ay - y - 7}px` : side === 'below' ? `top:-7px;left:${ax - x - 7}px` : `bottom:-7px;left:${ax - x - 7}px`;
  return abs(x, y, w, h, `<span class="pop-arrow" style="${arrow}"></span><div class="as-head"><b>${title}</b>${msg ? `<span>${msg}</span>` : ''}</div>` + actions.map((a) => `<div class="pop-btn ${a.role || ''}">${a.label}</div>`).join(''), 'glass popover');
}

function alertBox(cx, cy, title, msg, buttons, stacked) {
  const w = 270;
  const h = 44 + (msg ? 40 : 0) + (stacked ? buttons.length * 44 : 44) + 12;
  const btns = stacked
    ? buttons.map((b) => `<div class="al-btn ${b.role || ''}">${b.label}</div>`).join('')
    : `<div class="al-row">${buttons.map((b) => `<div class="al-btn ${b.role || ''}">${b.label}</div>`).join('')}</div>`;
  return abs(cx - w / 2, cy, w, null, `<div class="al-title">${title}</div>${msg ? `<div class="al-msg">${msg}</div>` : ''}${btns}`, 'glass alert', 'transform:translateY(-50%)');
}

// sheet with header (✕ title ✓); placement handled by caller
function sheet(x, y, w, h, title, body, o = {}) {
  const head = o.sideControls
    ? `<div class="sh-head"><span class="sh-title">${title}</span></div>`
    : `<div class="sh-head">${abs(12, 10, 44, 44, icon('xmark', 19), 'tb')}<span class="sh-title">${title}</span>${abs(w - 56, 10, 44, 44, icon('check', 20), 'tb on')}</div>`;
  return abs(x, y, w, h, head + `<div class="sh-body">${body}</div>`, 'sheet' + (o.grabber ? ' grab' : ''));
}

function formRows(rows) {
  return `<div class="form">${rows.map((r) => `<div class="form-row ${r.sel ? 'sel' : ''}"><span>${r.label}</span><span class="form-val">${r.value || ''}${r.sel ? icon('check', 16, 2.6) : ''}</span></div>`).join('')}</div>`;
}

// ---------- Frame + chips ----------

function frame(id, cfgKey, inner, chips = [], o = {}) {
  const cfg = CFG[cfgKey];
  return `<div class="cell" id="${id}">
    <div class="cellhead"><b>${id}</b><span>${o.caption || ''}</span></div>
    <div class="device ${o.cls || ''}" style="width:${o.w || cfg.w}px;height:${o.h || cfg.h}px;border-radius:${cfg.corner}px">${inner}${chrome(cfg, o)}</div>
    <div class="chips" style="max-width:${o.w || cfg.w}px">${chips.map((c) => `<span class="chip-meta ${c.kind || ''}">${c.text}</span>`).join('')}</div>
  </div>`;
}

// ---------- The layout rule (plan §7) ----------
// Wider than tall → two panes; taller than wide → stacked; an active division
// moves the split onto the fold. Board size comes from the container, never the device.

function boardGeom(k, st) {
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


// Transient banner / toast (S17c–e): glass capsule ≤ 480 pt, centered at (x, w), bottom edge at y
function transientBanner(x, w, y, kind, text) {
  const ww = Math.min(480, w);
  const dismiss = kind === 'dismiss' ? `<span class="tb" style="width:32px;height:32px;margin-left:auto;flex:none">${icon('xmark', 13)}</span>` : '';
  return abs(x + (w - ww) / 2, y - 52, ww, 52, `<span class="banner ${kind === 'toast' ? 'toast' : 'error'}" style="height:auto;min-height:40px;padding:8px 8px 8px 14px;white-space:normal;max-width:${ww}px">${icon(kind === 'toast' ? 'check' : 'warn', 15)}<span>${text}</span>${dismiss}</span>`, '', 'display:flex;justify-content:center;align-items:flex-end;z-index:48');
}
const BANNER_TEXT = { server: 'Couldn’t reach the server. Changes stay on this device until it answers.', dismiss: 'Couldn’t save the comment. Try again.', toast: 'PGN copied.' };

// ---------- Lists (shared by the Shell and Lists canvases) ----------


function shellGeom(k) {
  const cfg = CFG[k];
  const g = { k, cfg, compact: cfg.size.startsWith('C') };
  if (k === 'O') { g.bars = 'side'; g.cols = [{ x: 0, w: 382, kind: 'single' }]; g.top = 0; }
  else if (k === 'SVL') { g.bars = 'side'; g.cols = [{ x: 84, w: 371.5, kind: 'single' }]; g.top = 0; }
  else if (k === 'SVR') { g.bars = 'side'; g.cols = [{ x: 13.5, w: 371.5, kind: 'single' }]; g.top = 0; }
  else if (k === 'IL') { g.bars = 'side'; g.cols = [{ x: 0, w: 340, kind: 'sidebar' }, { x: 341, w: 526, kind: 'detail' }]; g.top = 0; }
  else if (k === 'FB') { g.bars = 'side'; g.cols = [{ x: 0, w: 455.5, kind: 'sidebar' }, { x: 495.5, w: 371.5, kind: 'detail' }]; g.top = 0; }
  else if (k === 'IP' || k === 'FT') { g.bars = 'nav'; g.cols = [{ x: 0, w: 300, kind: 'sidebar' }, { x: 301, w: 368, kind: 'detail' }]; g.top = 50; }
  else if (k === 'PD') { g.bars = 'nav'; g.cols = [{ x: 0, w: 360, kind: 'sidebar' }, { x: 361, w: 833, kind: 'detail' }]; g.top = 24; }
  g.contentX0 = g.cols[0].x; g.contentX1 = g.cols[g.cols.length - 1].x + g.cols[g.cols.length - 1].w;
  return g;
}



const tile = (ic, color, dim) => `<span class="itile" style="background:${color};opacity:${dim ? 0.4 : 1}">${icon(ic, 17, 2.4)}</span>`;
const ring = (pct) => `<span class="ring" style="background:conic-gradient(var(--accent-fill) ${pct * 3.6}deg, var(--fill2) 0)"><span>${pct}%</span></span>`;

function section(title, rows, o = {}) {
  return `${title ? `<div class="sec-h">${title}</div>` : ''}<div class="glist${o.cls ? ' ' + o.cls : ''}">${rows.join('')}</div>${o.footer ? `<div class="sec-f">${o.footer}</div>` : ''}`;
}
function row(o) {
  return `<div class="lrow ${o.cls || ''}" style="${o.style || ''}">${o.lead || ''}<span class="lr-main"><span class="lr-t">${o.title}${o.chip ? `<span class="inprog">${o.chip}</span>` : ''}</span>${o.sub ? `<span class="lr-s">${o.sub}</span>` : ''}</span>${o.trail || ''}${o.chev ? '<span class="chev">›</span>' : ''}</div>`;
}

function puzzlesList(st, w) {
  if (st.empty) return '';
  const practice = st.noPuzzles ? '' : section('Practice', [
    st.noSession ? '' : row({ lead: tile('skip', 'var(--accent)'), title: 'Resume Random Session', trail: '<span class="lr-v">5 left</span>' }),
    row({ lead: tile('sparkle', '#007aff'), title: 'Random From Everything' }),
    row({ lead: tile('flip', '#ff9500', st.noSession), title: 'Review Mistakes', cls: st.noSession ? 'dis' : '', trail: st.noSession ? '' : '<span class="badge">1</span>' }),
  ]);
  const cols = [
    { n: 'Back-rank mates', p: 33, s: '3 puzzles · 1 solved · 1 to review', chip: 'In progress' },
    { n: 'Missing pieces', p: 0, s: '3 puzzles · 0 solved' },
    { n: 'Endgame drills', p: 60, s: '20 puzzles · 12 solved' },
  ];
  const rows = cols.map((c, i) => {
    const sub = st.noPuzzles ? '0 puzzles' : c.s;
    const sel = st._split && i === 0 ? ' sel' : '';
    if (st.swipe && i === 0) return `<div class="swipewrap">${row({ lead: ring(c.p), title: c.n, sub, chip: c.chip, chev: true, cls: 'swiped' })}<span class="swipe-btn red">${icon('trash', 20)}<span>Delete</span></span></div>`;
    return row({ lead: ring(st.noPuzzles ? 0 : c.p), title: c.n, sub, chip: st.noPuzzles ? '' : c.chip, chev: !st._split, cls: sel + (st.overlay === 'ctx' && i === 0 ? ' lifted' : '') });
  });
  return practice + section('Collections', rows);
}

function gamesList(st) {
  if (st.empty) return '';
  const cols = [{ n: 'Club games', s: '24 games' }, { n: 'Study games', s: '8 games' }, { n: 'Openings', s: '1 game' }];
  const rows = cols.map((c, i) => {
    const sel = st._split && i === 0 ? ' sel' : '';
    if (st.swipe && i === 0) return `<div class="swipewrap">${row({ lead: tile('board', 'var(--accent)'), title: c.n, sub: c.s, chev: true, cls: 'swiped2' })}<span class="swipe-btn gray">${icon('pencil', 20)}<span>Rename</span></span><span class="swipe-btn red" style="right:0">${icon('trash', 20)}<span>Delete</span></span></div>`;
    return row({ lead: tile('board', 'var(--accent)'), title: c.n, sub: c.s, chev: !st._split, cls: sel + (st.overlay === 'ctx' && i === 0 ? ' lifted' : '') });
  });
  return section('', rows);
}

function cuv(ic, title, desc, btn, o = {}) {
  return `<div class="cuv" style="padding:0 20px"><div style="display:flex;justify-content:center;color:var(--label2)">${icon(ic, 46, 1.7)}</div><b>${title}</b>${desc}${btn ? `<div style="margin-top:14px;display:flex;flex-direction:column;align-items:center;gap:8px">${btn}</div>` : ''}</div>`;
}
const pbtn = (t, o = {}) => `<span class="btn ${o.prom ? 'prom' : 'glassbtn'}${o.dis ? ' dis' : ''}" style="flex:none;${o.red ? 'color:var(--red)' : ''}">${t}</span>`;


const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

if (typeof module !== 'undefined') module.exports = { CFG };
