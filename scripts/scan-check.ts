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

/** The newest format version the app understands. */
export const SCAN_VERSION = 1;

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

const QUICK_SCAN_KINDS = ['attacked', 'opened', 'undefended'];
const ARROW_SIDES = ['own', 'theirs'];
const ARROW_KINDS = ['check', 'capture', 'threat'];

type Raw = Record<string, unknown>;
const isObject = (value: unknown): value is Raw =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
const isSquare = (text: string) => /^[a-h][1-8]$/.test(text);
const absent = (value: unknown) => value === undefined || value === null;

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

/** Why one entry can't be played, or null. Reads and checks, as the app does. */
export function scanProblem(entry: unknown): string | null {
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
  if (!absent(entry.targets)) {
    if (!isObject(entry.targets)) return 'Malformed "targets"';
    for (const name of ['red', 'orange', 'kingZone', 'fork']) {
      const list = entry.targets[name];
      if (absent(list)) continue;
      if (!Array.isArray(list) || !list.every((s) => typeof s === 'string')) return 'Malformed "targets"';
    }
  }
  const arrows: { from: string; to: string }[] = [];
  if (!absent(entry.arrows)) {
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
      arrows.push({ from: item.from, to: item.to });
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

  // Checking: against the rules of chess.
  const chess = load(fen);
  if (!chess) return 'Malformed FEN';
  if (!play(chess, lastMove)) return `Last move ${lastMove} is illegal`;
  const start = chess.fen();

  if (isObject(entry.targets)) {
    for (const name of ['red', 'orange', 'kingZone', 'fork']) {
      squares.push(...((entry.targets[name] as string[] | undefined | null) ?? []));
    }
  }
  squares.push(...arrows.flatMap((a) => [a.from, a.to]));
  const bad = squares.find((s) => !isSquare(s));
  if (bad) return `Square ${bad} is not on the board`;
  for (const arrow of arrows) {
    if (!chess.get(arrow.from as Parameters<Chess['get']>[0])) {
      return `Arrow ${arrow.from}-${arrow.to} does not start on a piece`;
    }
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
  return null;
}

/** Reads `{"version": 1, "scan": [ ... ]}` as the app's import does. */
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
    const reason = scanProblem(entry);
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
