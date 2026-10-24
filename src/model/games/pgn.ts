import { Chess, DEFAULT_POSITION, validateFen } from 'chess.js';
import { parseUci } from '../move';
import type { Uci } from '../move';

/**
 * Games as PGN: a reader that keeps variations, and a writer that puts them
 * back.
 *
 * chess.js reads PGN too, but drops every variation without a word: `1. e4 e5
 * (1... c5) 2. Nf3` comes back as the main line alone. A game collection is
 * mostly *for* the variations, so the movetext is read here into a tree, and
 * chess.js is used for what it is good at — checking each move and saying
 * where it leads.
 *
 * The PGN text is what gets stored; the tree is only ever derived from it.
 */

export interface MoveNode {
  san: string;
  uci: Uci;
  /** The position after the move. */
  fen: string;
  /** Written before the move: how a variation is introduced. */
  before?: string;
  /** Written after the move. */
  comment?: string;
  /** Numeric annotation glyphs: 1 is `!`, 2 is `?`, and so on. */
  nags: number[];
  /** What follows. The first is the main line; the rest are alternatives to it. */
  children: MoveNode[];
}

export interface ParsedGame {
  /** In file order. `Result` is always present. */
  headers: Record<string, string>;
  /** From the `FEN` header, or the usual starting position. */
  startFen: string;
  /** Written before the first move: the note on the whole game. */
  comment?: string;
  /** The first moves: the main line's, then alternatives to it. */
  moves: MoveNode[];
}

export interface PgnError {
  /** Which game in the file, from 1. */
  game: number;
  message: string;
}

export const RESULTS = ['1-0', '0-1', '1/2-1/2', '*'] as const;

/** The order the PGN standard puts the first seven headers in. */
const SEVEN_TAG_ROSTER = ['Event', 'Site', 'Date', 'Round', 'White', 'Black', 'Result'];

/** The suffixes a move can be written with, and the glyph each stands for. */
const SUFFIX_NAGS: Record<string, number> = { '!': 1, '?': 2, '!!': 3, '??': 4, '!?': 5, '?!': 6 };

type Token =
  | { kind: 'header'; name: string; value: string }
  | { kind: 'comment'; text: string }
  | { kind: 'open' }
  | { kind: 'close' }
  | { kind: 'nag'; nag: number }
  | { kind: 'result'; result: string }
  | { kind: 'move'; san: string };

const HEADER_RE = /\[\s*([A-Za-z0-9_]+)\s*"((?:[^"\\]|\\.)*)"\s*\]/y;
const WORD_RE = /[^\s{}();[\]$]+/y;
const NAG_RE = /\$(\d+)/y;

function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  const restOfLine = () => {
    const end = text.indexOf('\n', i);
    const line = text.slice(i, end < 0 ? text.length : end);
    i = end < 0 ? text.length : end + 1;
    return line;
  };

  while (i < text.length) {
    const c = text[i];
    if (/\s/.test(c)) {
      i++;
    } else if (c === '%' && (i === 0 || text[i - 1] === '\n')) {
      // An escaped line, for whatever wrote the file. Not for us.
      restOfLine();
    } else if (c === '[') {
      HEADER_RE.lastIndex = i;
      const match = HEADER_RE.exec(text);
      if (!match) throw new Error(`A header is not written [Name "value"]: ${restOfLine().trim()}`);
      tokens.push({ kind: 'header', name: match[1], value: match[2].replace(/\\(.)/g, '$1') });
      i = HEADER_RE.lastIndex;
    } else if (c === '{') {
      const end = text.indexOf('}', i);
      if (end < 0) throw new Error('A comment is never closed');
      tokens.push({ kind: 'comment', text: text.slice(i + 1, end) });
      i = end + 1;
    } else if (c === ';') {
      i++;
      tokens.push({ kind: 'comment', text: restOfLine() });
    } else if (c === '(') {
      tokens.push({ kind: 'open' });
      i++;
    } else if (c === ')') {
      tokens.push({ kind: 'close' });
      i++;
    } else if (c === '$') {
      NAG_RE.lastIndex = i;
      const match = NAG_RE.exec(text);
      if (!match) throw new Error('A $ is not followed by a number');
      tokens.push({ kind: 'nag', nag: Number(match[1]) });
      i = NAG_RE.lastIndex;
    } else {
      WORD_RE.lastIndex = i;
      const word = WORD_RE.exec(text)![0];
      i = WORD_RE.lastIndex;
      tokens.push(...wordTokens(word));
    }
  }
  return tokens;
}

/** A run of text between the punctuation: a move, a move number, a result. */
function wordTokens(word: string): Token[] {
  if ((RESULTS as readonly string[]).includes(word)) return [{ kind: 'result', result: word }];
  // `12.`, `12...`, and `12.e4` with the space left out.
  const rest = word.replace(/^\d+\.+/, '');
  if (!rest) return [];
  if (rest in SUFFIX_NAGS) return [{ kind: 'nag', nag: SUFFIX_NAGS[rest] }];
  const match = /^(.*?)([!?]{1,2})?$/.exec(rest)!;
  const tokens: Token[] = [{ kind: 'move', san: match[1].replace(/^0-0(-0)?/, (m) => m.replace(/0/g, 'O')) }];
  if (match[2] && match[2] in SUFFIX_NAGS) tokens.push({ kind: 'nag', nag: SUFFIX_NAGS[match[2]] });
  return tokens;
}

/** Splits a file's tokens into games: a header after moves, or a result, ends one. */
function splitGames(tokens: Token[]): Token[][] {
  const games: Token[][] = [];
  let current: Token[] = [];
  let moved = false;
  let depth = 0;
  const close = () => {
    if (current.length) games.push(current);
    current = [];
    moved = false;
    depth = 0;
  };
  for (const token of tokens) {
    if (token.kind === 'header' && moved) close();
    current.push(token);
    if (token.kind !== 'header') moved = true;
    if (token.kind === 'open') depth++;
    if (token.kind === 'close') depth--;
    if (token.kind === 'result' && depth <= 0) close();
  }
  close();
  return games;
}

const cleanText = (text: string) => text.replace(/\s+/g, ' ').trim();

function joinComment(held: string | undefined, text: string): string | undefined {
  const cleaned = cleanText(text);
  if (!cleaned) return held;
  return held ? `${held} ${cleaned}` : cleaned;
}

/** Plays `move` (SAN, or anything chess.js accepts loosely) from `fen`. */
export function playFrom(fen: string, move: string): MoveNode {
  const chess = new Chess(fen);
  let played;
  try {
    played = chess.move(move, { strict: false });
  } catch {
    played = null;
  }
  if (!played) throw new Error(`${move} is not a legal move here`);
  return {
    san: played.san,
    uci: parseUci(played.lan)!,
    fen: played.after,
    nags: [],
    children: [],
  };
}

/** How a move is numbered: `12.` before White's, `12...` before Black's. */
export function moveNumber(fenBefore: string, alwaysForBlack: boolean): string | null {
  const [, side, , , , full] = fenBefore.split(' ');
  if (side === 'w') return `${full}.`;
  return alwaysForBlack ? `${full}...` : null;
}

function parseGame(tokens: Token[]): ParsedGame {
  const headers: Record<string, string> = {};
  let i = 0;
  for (; i < tokens.length && tokens[i].kind === 'header'; i++) {
    const header = tokens[i] as Extract<Token, { kind: 'header' }>;
    headers[header.name] = header.value;
  }

  let startFen = DEFAULT_POSITION;
  if (headers.FEN) {
    const check = validateFen(headers.FEN);
    if (!check.ok) throw new Error(`The FEN header is not a position: ${check.error}`);
    startFen = headers.FEN;
  }

  const game: ParsedGame = { headers, startFen, moves: [] };
  let result: string | undefined;

  /**
   * One line of play, into `list` from `fen`. A variation is an alternative to
   * the last move played, so it goes into that move's list, from the position
   * before it.
   */
  const line = (list: MoveNode[], fen: string, top: boolean) => {
    let last: { list: MoveNode[]; fenBefore: string; node: MoveNode } | null = null;
    let before: string | undefined;

    for (; i < tokens.length; i++) {
      const token = tokens[i];
      switch (token.kind) {
        case 'header':
          throw new Error('A header in the middle of the moves');
        case 'comment':
          if (last) last.node.comment = joinComment(last.node.comment, token.text);
          else if (top) game.comment = joinComment(game.comment, token.text);
          else before = joinComment(before, token.text);
          break;
        case 'nag':
          if (!last) throw new Error('An annotation before any move');
          last.node.nags.push(token.nag);
          break;
        case 'move': {
          let node: MoveNode;
          try {
            node = playFrom(fen, token.san);
          } catch {
            const number = moveNumber(fen, true);
            throw new Error(`${number} ${token.san} is not a legal move`);
          }
          if (before) node.before = before;
          before = undefined;
          list.push(node);
          last = { list, fenBefore: fen, node };
          list = node.children;
          fen = node.fen;
          break;
        }
        case 'open': {
          if (!last) throw new Error('A variation before any move');
          i++;
          line(last.list, last.fenBefore, false);
          break;
        }
        case 'close':
          if (top) throw new Error('A ) with no ( before it');
          return;
        case 'result':
          if (!top) throw new Error('A result inside a variation');
          result = token.result;
          break;
      }
    }
    if (!top) throw new Error('A ( is never closed');
  };

  line(game.moves, startFen, true);
  headers.Result = headers.Result ?? result ?? '*';
  return game;
}

/**
 * Every game in a PGN file. One that cannot be read is reported and skipped,
 * so a file with one bad game still brings in the rest.
 *
 * Text that is nothing but a FEN is read as a game with no moves yet, so a
 * position can be pasted on its own.
 */
export function parsePgnFile(text: string): { games: ParsedGame[]; errors: PgnError[] } {
  const trimmed = text.replace(/^﻿/, '').trim();
  if (trimmed && !trimmed.includes('\n') && validateFen(trimmed).ok) {
    return { games: [newGame(trimmed)], errors: [] };
  }

  let tokens: Token[];
  try {
    tokens = tokenize(trimmed);
  } catch (error) {
    return { games: [], errors: [{ game: 1, message: (error as Error).message }] };
  }
  const games: ParsedGame[] = [];
  const errors: PgnError[] = [];
  splitGames(tokens).forEach((game, index) => {
    try {
      games.push(parseGame(game));
    } catch (error) {
      errors.push({ game: index + 1, message: (error as Error).message });
    }
  });
  return { games, errors };
}

/** Reads one stored game, which was written by `writePgn` and so is known good. */
export function parsePgn(text: string): ParsedGame {
  const { games, errors } = parsePgnFile(text);
  if (errors.length) throw new Error(errors[0].message);
  return games[0] ?? newGame();
}

/**
 * Only the headers of a stored game: all a list needs, without reading every
 * move of every game in a collection to show it.
 */
export function readHeaders(pgn: string): Record<string, string> {
  const headers: Record<string, string> = {};
  const re = new RegExp(HEADER_RE.source, 'y');
  for (const line of pgn.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) {
      if (Object.keys(headers).length) break;
      continue;
    }
    re.lastIndex = 0;
    const match = re.exec(trimmed);
    if (!match) break;
    headers[match[1]] = match[2].replace(/\\(.)/g, '$1');
  }
  return headers;
}

/** The headers a new game starts with: the seven the standard asks for. */
export function newGame(startFen: string = DEFAULT_POSITION): ParsedGame {
  const headers: Record<string, string> = {
    Event: '?',
    Site: '?',
    Date: '????.??.??',
    Round: '?',
    White: '?',
    Black: '?',
    Result: '*',
  };
  if (startFen !== DEFAULT_POSITION) {
    headers.SetUp = '1';
    headers.FEN = startFen;
  }
  return { headers, startFen, moves: [] };
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

const escapeHeader = (value: string) => value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');

/** A comment cannot hold its own closing brace. */
const commentToken = (text: string) => `{${text.replace(/}/g, ')')}}`;

/** Space-separated tokens, wrapped to lines of at most 80 characters. */
function wrap(tokens: string[]): string {
  const lines: string[] = [];
  let current = '';
  for (const token of tokens) {
    if (current && current.length + 1 + token.length > 80) {
      lines.push(current);
      current = token;
    } else {
      current = current ? `${current} ${token}` : token;
    }
  }
  if (current) lines.push(current);
  return lines.join('\n');
}

/** The game as PGN text: headers, a blank line, the movetext. */
export function writePgn(game: ParsedGame): string {
  const names = [
    ...SEVEN_TAG_ROSTER.filter((name) => name in game.headers),
    ...Object.keys(game.headers).filter((name) => !SEVEN_TAG_ROSTER.includes(name)),
  ];
  const headerLines = names.map((name) => `[${name} "${escapeHeader(game.headers[name])}"]`);

  const out: string[] = [];
  let opening = false;
  const push = (token: string) => {
    out.push(opening ? `(${token}` : token);
    opening = false;
  };
  // Parentheses sit against what they enclose: `(1... c5)`.
  const open = () => (opening = true);
  const close = () => (out[out.length - 1] += ')');

  if (game.comment) push(commentToken(game.comment));

  /**
   * `list[0]` and what follows it, with `list[1..]` as variations after it.
   * Black's move is numbered `12...` whenever something has come between it
   * and White's: a comment, a variation, or the start of the line.
   */
  const line = (list: MoveNode[], fen: string, numbered: boolean) => {
    while (list.length) {
      const [main, ...alternatives] = list;
      move(main, fen, numbered);
      numbered = Boolean(main.comment);
      for (const alternative of alternatives) {
        open();
        move(alternative, fen, true);
        line(alternative.children, alternative.fen, Boolean(alternative.comment));
        close();
        numbered = true;
      }
      fen = main.fen;
      list = main.children;
    }
  };

  const move = (node: MoveNode, fen: string, numbered: boolean) => {
    if (node.before) push(commentToken(node.before));
    const number = moveNumber(fen, numbered || Boolean(node.before));
    // One token, so wrapping never parts a number from its move.
    push(number ? `${number} ${node.san}` : node.san);
    for (const nag of node.nags) push(`$${nag}`);
    if (node.comment) push(commentToken(node.comment));
  };

  line(game.moves, game.startFen, true);
  push(game.headers.Result ?? '*');

  return `${headerLines.join('\n')}\n\n${wrap(out)}\n`;
}
