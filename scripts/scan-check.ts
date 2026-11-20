/**
 * The scan puzzle checks, for the maker to run before sending a file.
 *
 * Scan Training is iOS only, so the app's checks are Swift
 * (`iOS/Motif/Motif/Model/Scan/ScanImport.swift`). This mirrors them rule for
 * rule and message for message; both run the same fixtures
 * (`iOS/Motif/MotifTests/Fixtures/scan/scan-import.json`), so they can't
 * drift apart unnoticed.
 */
import { Chess } from 'chess.js';

/**
 * The newest format version the app understands. 2 adds the full scan; 3 lets a
 * red or orange target be an empty king-zone square (next to either king); 4 adds
 * the quick-scan kind `unpinned`, optional arrows, and quick-scan squares must be pieces; 5
 * adds the quick-scan kind `hanging` (the top-level `spec`, the maker's rule version, is ignored); 6
 * drops `targets`: a Flag puzzle needs only `arrows`, and `targets` is ignored (unread, unchecked) in
 * every version. 7 plays the line out: a Flag puzzle may carry `solutions` (lines of UCI moves, both
 * sides, from the solver's first move) and any puzzle `bestCp` (the best move's eval, mate = 100000);
 * both are read only from 7.
 */
export const SCAN_VERSION = 7;

export interface ScanRejection {
  /** Index into the file's `scan` array; -1 for the whole file. */
  index: number;
  reason: string;
}

export interface ScanPuzzle {
  fenBefore: string;
  lastMove: string;
  flagged: boolean;
  key: string;
}

export interface ScanReadResult {
  puzzles: ScanPuzzle[];
  rejected: ScanRejection[];
}

const QUICK_SCAN_KINDS = ['attacked', 'opened', 'undefended', 'unpinned', 'hanging'];
const ARROW_SIDES = ['own', 'theirs'];
const ARROW_KINDS = ['check', 'capture', 'threat'];

type Raw = Record<string, unknown>;
const isObject = (value: unknown): value is Raw =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
const isSquare = (text: string) => /^[a-h][1-8]$/.test(text);
const absent = (value: unknown) => value === undefined || value === null;
type Square = Parameters<Chess['get']>[0];

function parseUci(text: string): string | null {
  const lower = text.trim().toLowerCase();
  return /^[a-h][1-8][a-h][1-8][qrbn]?$/.test(lower) ? lower : null;
}

/** Plays a UCI move; false when it's illegal. */
function play(chess: Chess, move: string): boolean {
  try {
    chess.move({ from: move.slice(0, 2), to: move.slice(2, 4), promotion: move[4] });
    return true;
  } catch {
    return false;
  }
}

function load(fen: string): Chess | null {
  try {
    return new Chess(fen);
  } catch {
    return null;
  }
}

export function scanContentKey(fenBefore: string, lastMove: string): string {
  return `${fenBefore.trim().split(/\s+/).slice(0, 4).join(' ')}/${lastMove}`;
}

function versionProblem(version: number): string | null {
  if (version < 1) return `Unknown format version ${version}`;
  if (version > SCAN_VERSION) {
    return `Format version ${version} is newer than this app understands (${SCAN_VERSION})`;
  }
  return null;
}

/** The position with `side` to move; handing the move over drops en passant. */
function withTurn(fen: string, side: 'w' | 'b'): string {
  const fields = fen.split(/\s+/);
  if (fields[1] === side) return fen;
  fields[1] = side;
  fields[3] = '-';
  return fields.join(' ');
}

interface Arrow {
  from: string;
  to: string;
  side: string;
  kind: string;
}

/** Version 2: what the full scan must hold (ScanImport.fullScanProblem). */
function fullScanProblem(entry: Raw, arrows: Arrow[] | null, chess: Chess): string | null {
  if (entry.flagged && !arrows) return 'Flag puzzle is missing "arrows"';
  if (!arrows) return null;
  const start = chess.fen();
  const solver = chess.turn();
  const lines = new Set<string>();
  for (const arrow of arrows) {
    const name = `${arrow.from}-${arrow.to}`;
    if (lines.has(arrow.from + arrow.to)) return `Arrow ${name} is listed twice`;
    lines.add(arrow.from + arrow.to);
    const piece = chess.get(arrow.from as Square);
    if (!piece) return `Arrow ${name} does not start on a piece`;
    const side = piece.color === solver ? 'own' : 'theirs';
    if (arrow.side !== side) {
      return `Arrow ${name} is "${arrow.side}" but starts on ${side === 'own' ? "the solver's" : "the opponent's"} piece`;
    }
    const moves = (load(withTurn(start, piece.color))?.moves({ square: arrow.from as Square, verbose: true }) ?? [])
      .filter((m) => m.to === arrow.to);
    if (!moves.length) return `Arrow ${name} is not a legal move`;
    if (arrow.kind === 'capture' && !moves.some((m) => m.san.includes('x'))) return `Arrow ${name} is not a capture`;
    if (arrow.kind === 'check' && !moves.some((m) => /[+#]$/.test(m.san))) return `Arrow ${name} does not give check`;
  }
  return null;
}

/** Why one entry can't be played, or null. Reads and checks, as the app does. */
export function scanProblem(entry: unknown, version: number): string | null {
  if (!isObject(entry)) return 'Not an object';
  const fen = entry.fenBefore;
  if (typeof fen !== 'string') return 'Malformed FEN';
  if (typeof entry.lastMove !== 'string') return 'Missing "lastMove"';
  const lastMove = parseUci(entry.lastMove);
  if (!lastMove) return `Last move ${entry.lastMove} is malformed`;
  if (typeof entry.flagged !== 'boolean') return 'Missing "flagged"';

  // Reading: shapes and names.
  if (!Array.isArray(entry.quickScan)) return 'Missing a "quickScan" array';
  const squares: string[] = [];
  for (const item of entry.quickScan) {
    if (!isObject(item) || typeof item.square !== 'string') return 'Malformed quick-scan square';
    if (typeof item.kind !== 'string' || !QUICK_SCAN_KINDS.includes(item.kind)) {
      return `Unknown quick-scan kind for ${item.square}`;
    }
    squares.push(item.square);
  }
  // `targets` (before v6) is ignored: nothing grades or shows it any more.
  let arrows: Arrow[] | null = null;
  if (!absent(entry.arrows)) {
    arrows = [];
    if (!Array.isArray(entry.arrows)) return 'Malformed "arrows"';
    for (const item of entry.arrows) {
      if (!isObject(item) || typeof item.from !== 'string' || typeof item.to !== 'string') {
        return 'Malformed arrow';
      }
      if (typeof item.side !== 'string' || !ARROW_SIDES.includes(item.side)) {
        return `Unknown arrow side for ${item.from}-${item.to}`;
      }
      if (typeof item.kind !== 'string' || !ARROW_KINDS.includes(item.kind)) {
        return `Unknown arrow kind for ${item.from}-${item.to}`;
      }
      if (!absent(item.optional) && typeof item.optional !== 'boolean') {
        return `Malformed "optional" for arrow ${item.from}-${item.to}`;
      }
      arrows.push({ from: item.from, to: item.to, side: item.side, kind: item.kind });
    }
  }
  if (!isObject(entry.moves)) return 'Missing a "moves" object';
  const moves = new Map<string, number>();
  for (const [text, score] of Object.entries(entry.moves)) {
    const move = parseUci(text);
    if (!move) return `Move ${text} is malformed`;
    if (typeof score !== 'number' || !Number.isInteger(score)) {
      return `Move ${text} has no whole-number score`;
    }
    moves.set(move, score);
  }
  let bestLine: string[] | null = null;
  if (!absent(entry.bestLine)) {
    if (!Array.isArray(entry.bestLine)) return 'Malformed "bestLine"';
    const line = entry.bestLine.map((m) => (typeof m === 'string' ? parseUci(m) : null));
    if (line.some((m) => m === null)) return 'Best line contains a malformed move';
    bestLine = line as string[];
  }
  // The line and the best eval (v7); older versions never read them.
  let solutions: string[][] | null = null;
  if (version >= 7) {
    if (!absent(entry.solutions)) {
      if (!Array.isArray(entry.solutions)) return 'Malformed "solutions"';
      solutions = [];
      for (const [index, raw] of entry.solutions.entries()) {
        if (!Array.isArray(raw)) return `Line ${index + 1} is not a list of moves`;
        const line = raw.map((m) => (typeof m === 'string' ? parseUci(m) : null));
        if (line.some((m) => m === null)) return `Line ${index + 1} contains a malformed move`;
        solutions.push(line as string[]);
      }
    }
    if (!absent(entry.bestCp) && (typeof entry.bestCp !== 'number' || !Number.isInteger(entry.bestCp))) {
      return '"bestCp" is not a whole number';
    }
  }

  // Checking: against the rules of chess.
  const chess = load(fen);
  if (!chess) return 'Malformed FEN';
  if (!play(chess, lastMove)) return `Last move ${lastMove} is illegal`;
  const start = chess.fen();

  squares.push(...(arrows ?? []).flatMap((a) => [a.from, a.to]));
  const bad = squares.find((s) => !isSquare(s));
  if (bad) return `Square ${bad} is not on the board`;
  for (const arrow of arrows ?? []) {
    if (!chess.get(arrow.from as Square)) {
      return `Arrow ${arrow.from}-${arrow.to} does not start on a piece`;
    }
  }
  // Quick scan flags name pieces, never empty squares (v4).
  if (version >= 4) {
    for (const item of entry.quickScan as Raw[]) {
      if (!chess.get(item.square as Square)) return `Quick-scan square ${item.square} is not a piece`;
    }
  }
  if (version >= 2) {
    const problem = fullScanProblem(entry, arrows, chess);
    if (problem) return problem;
  }

  const legal = chess.moves({ verbose: true }).map((m) => m.from + m.to + (m.promotion ?? ''));
  if (!legal.length) return 'The solver has no legal move';
  const legalSet = new Set(legal);
  const listed = [...moves.keys()].sort();
  const illegal = listed.find((m) => !legalSet.has(m));
  if (illegal) return `Move ${illegal} is illegal`;
  const missing = legal.filter((m) => !moves.has(m));
  if (missing.length) {
    return (
      `Moves are missing ${missing.length} legal move${missing.length === 1 ? '' : 's'}: ` +
      missing.slice(0, 5).join(', ') +
      (missing.length > 5 ? ', …' : '')
    );
  }
  const negative = listed.find((m) => moves.get(m)! < 0);
  if (negative) return `Move ${negative} has a negative score`;
  if (![...moves.values()].includes(0)) return 'No move is scored 0 (the best)';

  if (bestLine) {
    const replay = new Chess(start);
    for (const [ply, move] of bestLine.entries()) {
      if (!play(replay, move)) return `Best line move ${move} is illegal at ply ${ply + 1}`;
    }
  }
  if (solutions) {
    if (!entry.flagged) return 'No flag puzzle has "solutions"';
    if (!solutions.length) return '"solutions" has no lines';
    for (const [index, line] of solutions.entries()) {
      if (!line.length) return `Line ${index + 1} is empty`;
      const replay = new Chess(start);
      for (const [ply, move] of line.entries()) {
        if (!play(replay, move)) return `Line ${index + 1} move ${move} is illegal at ply ${ply + 1}`;
      }
    }
  }
  return null;
}

/** Reads `{"version": 7, "spec": 7, "scan": [ ... ]}` as the app's import does. */
export function readScan(text: string): ScanReadResult {
  const result: ScanReadResult = { puzzles: [], rejected: [] };
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    result.rejected.push({ index: -1, reason: `Not valid JSON: ${(error as Error).message}` });
    return result;
  }
  if (!isObject(parsed) || !Array.isArray(parsed.scan)) {
    result.rejected.push({ index: -1, reason: 'Missing a "scan" array' });
    return result;
  }
  const version = parsed.version;
  if (typeof version !== 'number' || !Number.isInteger(version)) {
    result.rejected.push({ index: -1, reason: 'Missing "version"' });
    return result;
  }
  const versionReason = versionProblem(version);
  if (versionReason) {
    result.rejected.push({ index: -1, reason: versionReason });
    return result;
  }
  const positions = new Map<string, number>();
  parsed.scan.forEach((entry: unknown, index: number) => {
    const reason = scanProblem(entry, version);
    if (reason) {
      result.rejected.push({ index, reason });
      return;
    }
    const raw = entry as Raw;
    const lastMove = parseUci(raw.lastMove as string)!;
    const puzzle: ScanPuzzle = {
      fenBefore: raw.fenBefore as string,
      lastMove,
      flagged: raw.flagged as boolean,
      key: scanContentKey(raw.fenBefore as string, lastMove),
    };
    const at = positions.get(puzzle.key);
    if (at === undefined) {
      positions.set(puzzle.key, result.puzzles.length);
      result.puzzles.push(puzzle);
    } else {
      result.puzzles[at] = puzzle;
    }
  });
  return result;
}
