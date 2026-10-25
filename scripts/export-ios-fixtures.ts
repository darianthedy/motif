import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess, DEFAULT_POSITION, validateFen } from 'chess.js';
import * as board from '../src/model/board';
import * as move from '../src/model/move';
import { contentKey, normalizeFen, parsePlacement, placementText, solverSide } from '../src/model/puzzle';
import type { Placement, Puzzle, PuzzleContent } from '../src/model/puzzle';
import { importJson } from '../src/model/import/json';
import { PuzzleRunner } from '../src/model/runner';
import { makeQueue, orderForGlobalDraw } from '../src/model/session';
import { puzzleRecords, recentIds, runProgress } from '../src/model/derive';
import { allPuzzles, collectionsOf, planImport, progressOf, puzzlesIn, resumable, runIn } from '../src/model/library';
import type { Attempt, Library, Run } from '../src/data/backend';
import * as pgn from '../src/model/games/pgn';
import * as edit from '../src/model/games/edit';
import * as table from '../src/model/games/table';
import * as summary from '../src/model/games/summary';
import * as gameLibrary from '../src/model/games/library';
import type { Game } from '../src/model/games/game';

export const fixtureDirectory = fileURLToPath(
  new URL('../iOS/Motif/MotifTests/Fixtures/', import.meta.url),
);

const mate = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';
const promotion = '4k3/P7/8/8/8/8/8/4K3 w - - 0 1';
const kings = '4k3/8/8/8/8/8/8/4K3';

/** Inputs are authored; every expected value is produced by the real web API. */
function positionInputs(): { name: string; fen: string }[] {
  const positions = [
    { name: 'start', fen: DEFAULT_POSITION },
    { name: 'mate-in-one', fen: mate },
    { name: 'black-to-move', fen: mate.replace(' w ', ' b ') },
    { name: 'checkmate', fen: 'R5k1/5ppp/8/8/8/8/8/6K1 b - - 1 1' },
    { name: 'stalemate', fen: '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1' },
    { name: 'pinned-rook', fen: '4k3/8/8/8/8/4q3/4R3/4K3 w - - 0 1' },
    { name: 'pawn-capture', fen: '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1' },
    { name: 'white-promotion', fen: promotion },
    { name: 'black-promotion', fen: '4k3/8/8/8/8/8/p7/4K3 b - - 8 12' },
    { name: 'promotion-capture', fen: '1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1' },
    { name: 'castle-both', fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 17 9' },
    { name: 'castle-black', fen: 'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 17 9' },
    { name: 'castle-through-check', fen: '4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1' },
    { name: 'castle-in-check', fen: '4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1' },
    { name: 'stale-castling-rights', fen: `${kings} w KQkq - 0 1` },
    { name: 'rook-capture-revokes-rights', fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 4 7' },
    { name: 'en-passant', fen: '4k3/8/8/3pP3/8/8/8/4K3 w - d6 7 13' },
    { name: 'black-en-passant', fen: '4k3/8/8/8/3Pp3/8/8/4K3 b - d3 7 13' },
    { name: 'pinned-en-passant', fen: 'k3r3/8/8/3pP3/8/8/8/4K3 w - d6 7 13' },
    { name: 'double-push-capturable', fen: '4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1' },
    { name: 'double-push-pinned-capturer', fen: '4k3/8/8/8/3p4/8/4P3/3RK3 w - - 0 1' },
    { name: 'ep-without-capturer', fen: `${kings} w - d6 0 1` },
    { name: 'ep-without-pawn', fen: '4k3/8/8/4P3/8/8/8/4K3 w - d6 0 1' },
    { name: 'disambiguate-file', fen: '4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1' },
    { name: 'disambiguate-rank', fen: '4k3/8/8/8/8/R7/8/R3K3 w - - 0 1' },
    { name: 'disambiguate-both', fen: '7k/8/8/1N6/8/1N3N2/8/4K3 w - - 0 1' },
    { name: 'other-side-in-check-accepted', fen: '4k3/8/8/8/8/8/4R3/4K3 w - - 0 1' },
    { name: 'short-two-fields', fen: `${kings} w` },
    { name: 'short-three-fields', fen: `${kings} b -` },
    { name: 'short-four-fields', fen: `${kings} w - -` },
    { name: 'short-five-fields', fen: `${kings} w - - 8` },
    { name: 'multiple-whitespace', fen: `${kings}\tw  -\t-  0  1` },
    { name: 'counter-prefixes', fen: `${kings} w - - 2junk +003tail` },
    { name: 'negative-zero-counter', fen: `${kings} w - - -0 1` },
    { name: 'large-counters', fen: `${kings} w - - 9007199254740993 1000000000000000000000` },
    { name: 'ecmascript-whitespace', fen: `${kings}\uFEFFw\u00A0-\u2028- 0 1` },
    { name: 'zero-in-rank-accepted', fen: '4k0r2/8/8/8/8/8/8/4K3 w - - 0 1' },
    { name: 'duplicate-castling-symbols', fen: `${kings} w QKK-q - 0 1` },
  ];
  // A deterministic walk checks ordinary positions beyond handpicked edge cases.
  const chess = new Chess();
  let state = 0x51ce;
  for (let ply = 0; ply < 72; ply++) {
    const moves = chess.moves({ verbose: true });
    if (!moves.length) break;
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    chess.move(moves[state % moves.length]);
    if (ply % 3 === 0) positions.push({ name: `walk-${ply}`, fen: chess.fen() });
  }
  return positions;
}

const invalidFens = [
  '', 'garbage', kings, `${kings} w - - 0 1 extra`,
  ` ${kings} w - - 0 1`, `${kings} w - - 0 1 `,
  `${kings} w - - 0 0`, `${kings} w - - -1 1`, `${kings} w - - x 1`,
  `${kings} w - - 0 x`, `${kings} w - z6 0 1`, `${kings} w - a4 0 1`,
  `${kings} w - a3 0 1`, `${kings} b - a6 0 1`, `${kings} x - - 0 1`,
  `${kings} w X - 0 1`, '4k3/8/8/8/8/8/4K3 w - - 0 1',
  '4k3/8/8/8/8/8/8/4K4 w - - 0 1', '4k3/8/8/8/8/8/8/44 w - - 0 1',
  '4k3/8/8/8/8/8/8/4Z3 w - - 0 1', '8/8/8/8/8/8/8/4K3 w - - 0 1',
  '4k3/8/8/8/8/8/8/8 w - - 0 1', '4k3/8/8/8/8/8/8/3KK3 w - - 0 1',
  '3kk3/8/8/8/8/8/8/4K3 w - - 0 1', 'P3k3/8/8/8/8/8/8/4K3 w - - 0 1',
  '4k3/8/8/8/8/8/8/p3K3 w - - 0 1', `${kings}\u0085w - - 0 1`,
];

function playSan(fen: string, text: string) {
  try {
    const chess = new Chess(fen);
    const played = chess.move(text, { strict: false });
    return { san: played.san, uci: played.lan, fenAfter: chess.fen() };
  } catch {
    return null;
  }
}

function generateBoard() {
  const inputs = [' e2E4 ', 'a7a8q', 'a7a8n', 'a7a8r', 'a7a8b', 'a1a1',
    'a0a1', 'i1a1', 'e2e4k', 'e2-e4', 'e2e4qq', '', 'e2e4\n', 'e2e4♞',
    '\uFEFFe2e4\u00A0', '\u0085e2e4\u0085'];
  const queries = [...board.SQUARES, 'zz', 'a9', 'A1', 'a10', ''];
  const positions = positionInputs().map(({ name, fen }) => {
    const chess = new Chess(fen);
    const legal = chess.moves({ verbose: true });
    const ucis = [...new Set([...legal.map((m) => m.lan), 'a1b2', 'd4d5', 'e2e5',
      'e1e1', 'a7a8', 'a7a8q', 'a7a8n', 'e2e4q'])];
    const sanInputs = [...new Set([
      ...legal.map((m) => m.san), ...legal.map((m) => m.san.replace(/[+#]$/, '')),
      ...legal.slice(0, 5).flatMap((m) => [m.lan, `${m.piece}${m.from}-${m.to}${m.promotion ?? ''}`]),
      'Nf3', 'ng1f3', 'Nge2', 'Pe2-e4', '0-0', '0-0-0', 'e8Q', 'bogus', '--',
    ])];
    const placements: Placement[] = ['a1', 'a8', 'd4', 'g6', 'e1', 'e8', 'zz'].flatMap(
      (square) => (['w', 'b'] as const).flatMap((color) =>
        (['q', 'n', 'p', 'k'] as const).map((type) => ({ square, color, type }))),
    );
    const line = name === 'start' ? ['e2e4', 'e7e5', 'g1f3', 'a8a1'] :
      name === 'mate-in-one' ? ['a1a8', 'g8h8'] : [ucis[0], 'a1b2'];
    const solutions = [line.map(move.uci), [], [move.uci('a1b2')]];
    return {
      name, fen, validation: validateFen(fen), valid: board.isValidFen(fen),
      turn: board.turnOf(fen), checkmate: board.isCheckmate(fen),
      targets: queries.map((from) => ({
        from, destinations: Object.fromEntries(board.targetsFrom(fen, from)),
      })),
      moves: ucis.map((text) => {
        const uci = move.uci(text);
        return { uci, legal: board.isLegal(fen, uci), san: board.sanFor(fen, uci),
          fenAfter: board.applyUci(fen, uci) };
      }),
      sans: sanInputs.map((text) => ({ text, played: playSan(fen, text) })),
      pieces: queries.map((square) => ({ square, piece: board.pieceAt(fen, square) })),
      empty: board.emptySquares(fen),
      placements: placements.map((placement) => ({
        placement, fenAfter: board.withPiece(fen, placement),
      })),
      line, replay: board.replayLine(fen, line.map(move.uci)),
      solutions, firstIllegal: board.firstIllegalMove(fen, solutions),
    };
  });
  return {
    version: 1, defaultPosition: DEFAULT_POSITION, squares: board.SQUARES,
    uci: inputs.map((text) => {
      const parsed = move.parseUci(text);
      return { text, parsed, from: parsed ? move.moveFrom(parsed) : null,
        to: parsed ? move.moveTo(parsed) : null,
        promotion: parsed ? move.movePromotion(parsed) : null,
        stripped: parsed ? move.stripQueenPromotion(parsed) : null };
    }),
    invalid: invalidFens.map((fen) => ({
      fen, valid: board.isValidFen(fen), validation: validateFen(fen),
      checkmate: board.isCheckmate(fen), targets: Object.fromEntries(board.targetsFrom(fen, 'e1')),
      piece: board.pieceAt(fen, 'e1'), empty: board.emptySquares(fen),
    })),
    positions,
    mating: [{ fen: '6k1/5ppp/8/8/8/8/8/6K1 b - - 0 1', color: 'w' as const }]
      .map(({ fen, color }) => ({ fen, color, placements: board.matingPlacements(fen, color) })),
  };
}

const missing = '6rk/6pp/8/1p1b4/p7/3P4/PPP5/1K5R b - - 0 1';
const knight: Placement = { color: 'w', type: 'n', square: 'g6' };
const puzzleContent = (lines: string[][], fen = mate): PuzzleContent =>
  ({ fen, solutions: lines.map((line) => line.map(move.uci)), tags: [] });
const makePuzzle = (content: PuzzleContent, id = 'p', collectionId = 'c', position = 0): Puzzle =>
  ({ ...content, id, collectionId, position, addedAt: 0 });

function generateContentKeys() {
  const inputs: PuzzleContent[] = [
    puzzleContent([['a1a8']]), puzzleContent([['a1b1'], ['a1a8']]),
    puzzleContent([['a1a8'], ['a1b1']], mate.replace('0 1', '9 42')),
    puzzleContent([['d1h5', 'g7g6', 'h5g6'], ['d1h5', 'g7g6', 'h5e8']]),
    puzzleContent([['e7e8']]), puzzleContent([['e7e8q']]), puzzleContent([['e7e8n']]),
    puzzleContent([[], ['a1a8'], ['a1a8']]),
    puzzleContent([['a1a8']], ` \uFEFF${mate.replaceAll(' ', '\u00A0\t')} \n`),
    puzzleContent([], ''), puzzleContent([], `${kings} b`),
    { ...puzzleContent([], missing), addPiece: knight },
    { ...puzzleContent([], missing), addPiece: { ...knight, type: 'q' } },
    { ...puzzleContent([], missing), addPiece: { ...knight, color: 'b' } },
    { ...puzzleContent([['a1a8']]), comment: 'Unicode ♞ and spoilers', tags: ['mate'], rating: 900, sourceId: '187' },
  ];
  const placements = [
    'Ng6', 'ng6', '  Q f8 ', 'bNg6', 'wng6', 'bg6', 'bBg6', 'pa2',
    'w - N - g6', '\uFEFFQ\u00A0f8\uFEFF', 'N\u0085g6', 'Ng6\n',
    '', 'g6', 'Xg6', 'Ng9', 'Nj6', 'Ng6g7', 'knight g6', 'NG6',
  ].map((text) => {
    const parsed = parsePlacement(text);
    return { text, parsed, canonical: parsed ? placementText(parsed) : null };
  });
  return { version: 1, cases: inputs.map((input) =>
    ({ input, key: contentKey(input), normalizedFen: normalizeFen(input.fen), side: solverSide(input) })), placements };
}

function generateImports() {
  const entry = { fen: mate, solutions: [['a1a8']] };
  const single = (puzzles: unknown[], collection: unknown = 'Fixture') =>
    JSON.stringify({ collection, puzzles });
  const cases = [
    { name: 'metadata', text: single([
      { ...entry, id: 187, tags: ['mate', 7, false, null], comment: '', rating: 900 },
      { ...entry, solutions: [['a1a7']], id: '12b', tags: 'mate', comment: false, rating: true },
      { ...entry, solutions: [['a1a6']], id: false, rating: '900' },
    ]) },
    { name: 'number-ids', text: single([0, -0, 1.25, 1e-7, 1e-6, 1e20, 1e21, -1e21, 9007199254740992]
      .map((id) => ({ fen: missing, add_piece: 'Ng6', id, solutions: [] }))) },
    // Separate groups ensure numeric source ids do not dedupe each other away.
    { name: 'number-id-groups', text: JSON.stringify([0, -0, 1.25, 1e-7, 1e-6, 1e20, 1e21, -1e21, 9007199254740992]
      .map((id) => ({ puzzles: [{ ...entry, id }] }))) },
    { name: 'bad-entries', text: single([
      null, {}, { fen: 'nonsense' }, { ...entry, solutions: [] },
      { ...entry, solutions: [['a1a8', 'g8g7']] }, { ...entry, solutions: [['a1z9']] },
      { ...entry, solutions: [null] }, { ...entry, solutions: [[]] }, { ...entry, solutions: [[7]] },
      { ...entry, solutions: [['a1b2']] }, { ...entry, solutions: [['a1a8'], ['a1b2']] },
    ]) },
    { name: 'normalization', text: single([{ ...entry, solutions: [[' A1A8 ']], add_piece: null }], 7) },
    { name: 'forced-reply', text: single([
      { fen: '6k1/5p1p/8/8/8/8/8/3R2K1 w - - 0 1', solutions: [['d1d8', 'g8g7']] },
      { fen: '1r1k4/2R4R/8/8/8/6pP/PPP4q/K1B5 w - - 0 1', solutions: [['c1g5', 'd8e8', 'h7h8']] },
      { fen: '2rrk1n1/1nQ1p2N/pB5p/6p1/qP3p2/2P4P/P3BPP1/3R2K1 w - - 0 1', solutions: [['c7d8', 'e8d8', 'd1d8']] },
    ]) },
    { name: 'duplicate-order-last-metadata', text: single([
      { ...entry, tags: ['a'] }, { ...entry, solutions: [['a1a7']] },
      { ...entry, fen: mate.replace('0 1', '5 9'), tags: ['b'] },
    ]) },
    { name: 'multiple-groups', text: JSON.stringify([
      { collection: 'A', puzzles: [entry] }, { collection: 'B', puzzles: [entry, { fen: 'bad' }] },
    ]) },
    { name: 'missing-arrays-indices', text: JSON.stringify([
      null, 7, {}, { puzzles: [entry] }, { puzzles: 'no' }, { puzzles: [false, entry] },
    ]) },
    { name: 'empty-groups', text: JSON.stringify([{ collection: '', puzzles: [] }, { puzzles: [] }]) },
    { name: 'empty-array', text: '[]' },
    { name: 'primitive', text: 'null' },
    { name: 'missing-piece-cases', text: single([
      { fen: missing, add_piece: 'Ng6' }, { fen: missing, add_piece: 'wng6', solutions: null },
      { fen: missing, add_piece: 'Ng6', solutions: [['g8g7']] },
      ...['Kg6', 'Ng7', 'Pg1', 'knight to g6', 7, false, ''].map((add_piece) =>
        ({ fen: missing, solutions: [], add_piece })),
    ]) },
    { name: 'sample-missing-piece', text: readFileSync(fileURLToPath(new URL('../samples/missing-piece.json', import.meta.url)), 'utf8') },
    ...['{ not json', '', '{"puzzles": [}', '{"puzzles": []} trailing'].map((text, i) =>
      ({ name: `invalid-json-${i}`, text })),
  ];
  return { version: 1, cases: cases.map((input) => ({ ...input, expected: importJson(input.text) })) };
}

function seeded(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

/** Extra parity for APIs without their own TS tests and exact seeded shuffles. */
function generatePuzzleModel() {
  const sessions = [0, 1, 5, 42, 0xffffffff].flatMap((seed) => [0, 1, 6, 50].map((n) => {
    const ids = Array.from({ length: n }, (_, i) => `p${i}`);
    const recent = ids.slice(0, 28);
    return { seed, ids, recent,
      queues: Object.fromEntries((['ordered', 'randomInCollection', 'randomGlobal', 'reviewMistakes'] as const)
        .map((mode) => [mode, makeQueue(mode, ids, seeded(seed))])),
      global: orderForGlobalDraw(ids, recent, seeded(seed)) };
  }));
  const runnerInputs = [
    { lines: [['a1a8'], ['a1a8', 'g8g7', 'a8a7']], moves: ['a1a7', 'a1a7', 'a1a6', 'a1a8', 'a8a7', 'a8h8'] },
    { lines: [['a1a8', 'g8g7', 'a8a7'], ['a1a8', 'h7h6', 'a8h8']], moves: ['a1a8', 'a8h8', 'a8a7'] },
    { lines: [['e7e8'], ['e7e8n']], moves: ['e7e8r', 'e7e8q', 'e7e8n'] },
    { lines: [['e7e8q']], moves: ['e7e8', 'e7e8n', 'e7e8r', 'e7e8q'] },
    { lines: [['a1a8', 'g8g7'], ['a1a8']], moves: ['a1a8'] },
    { lines: [], moves: ['a1a7', 'a1a7', 'a1a7'] },
  ];
  const runners = runnerInputs.map(({ lines, moves }) => {
    const puzzle = makePuzzle(puzzleContent(lines));
    const runner = new PuzzleRunner(puzzle);
    return { puzzle, moves: moves.map((text) => {
      const outcome = runner.submit(move.uci(text));
      const hint = runner.revealHint();
      return { move: text, outcome, hint, accepted: [...runner.accepted], misses: [...runner.misses],
        wrongAtThisPly: runner.wrongAtThisPly, complete: runner.complete, hinted: runner.hinted, result: runner.result };
    }) };
  });
  const run: Run = { id: 'run', scope: 'c', mode: 'ordered', queue: ['a', 'b', 'deleted', 'c'], startedAt: 0 };
  const attempts: Attempt[] = [
    { id: 'z', puzzleId: 'a', runId: 'run', result: 'failed', mistakes: 2, hinted: true, playedAt: 1 },
    { id: 'a', puzzleId: 'a', runId: 'run', result: 'solved', mistakes: 0, hinted: false, playedAt: 1 },
    { id: 'b', puzzleId: 'b', runId: null, result: 'failed', mistakes: 1, hinted: false, playedAt: 2 },
    { id: 'c', puzzleId: 'b', runId: 'run', result: 'skipped', mistakes: 0, hinted: false, playedAt: 3 },
  ];
  const library: Library = { collections: [
    { id: 'd', name: 'Second', createdAt: 1 }, { id: 'c', name: 'First', createdAt: 1 },
  ], puzzles: [
    makePuzzle(puzzleContent([['a1a6']]), 'b', 'c', 0),
    makePuzzle(puzzleContent([['a1a7']]), 'a', 'c', 0),
    makePuzzle(puzzleContent([['a1a8']]), 'c', 'd', 2),
    makePuzzle(puzzleContent([['a1a8']]), 'orphan', 'absent', 0),
  ], runs: [run], attempts, gameCollections: [], games: [] };
  const incoming = [puzzleContent([['a1a7']]), puzzleContent([['a1b1']]), puzzleContent([['a1b1']])];
  const emptyIdLibrary: Library = { ...library,
    puzzles: [makePuzzle(puzzleContent([['a1a8']]), '', 'c')],
    runs: [{ ...run, queue: [''] }], attempts: [] };
  return { version: 1, sessions, runners, library: { input: library, incoming,
    collections: collectionsOf(library), puzzles: puzzlesIn(library, 'c'), all: allPuzzles(library),
    run: runIn(library, 'c'), progress: progressOf(library, run), resumable: resumable(library, 'c'),
    absentResumable: resumable(library, 'absent'), plan: planImport(puzzlesIn(library, 'c'), incoming, 'c'),
    records: Object.fromEntries(puzzleRecords(attempts)), recent: recentIds(attempts),
    emptyProgress: runProgress({ ...run, queue: [] }, attempts, new Set()) },
    emptyIdResume: { input: emptyIdLibrary, expected: resumable(emptyIdLibrary, 'c') } };
}

const annotatedPgn = `[Event "Club night"]
[Site "?"]
[Date "2024.03.??"]
[Round "?"]
[White "Me"]
[Black "Them"]
[Result "1-0"]

{An old favourite.} 1. e4 e5 (1... c5 {Sicilian} 2. Nf3 (2. c3) d6) 2. Nf3! Nc6
3. Bb5 $1 a6 (3... Nf6 4. O-O) 4. Ba4 ; to the end of the line
Nf6 1-0
`;

function pgnInputs() {
  const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 30';
  const inputs = [
    { name: 'annotated', input: annotatedPgn },
    { name: 'black-fen-start', input: `[SetUp "1"]\n[FEN "${fen}"]\n\n30... h6 31. Ra8+ Kh7 *` },
    { name: 'variation-before', input: '1. e4 ({or} 1. d4 d5) e5 *' },
    { name: 'loose-moves', input: '1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.0-0 Nf6!? *' },
    { name: 'glyph-words', input: '1. e4 e5 = 2. Nf3 ⩱ (2. Qh5 ⨀) Nc6 +/- 3. Bb5 -+ *' },
    { name: 'nested-variations', input: '1. e4 e5 (1... c5 2. Nf3 (2. c3 (2. Nc3)) d6 (2... Nc6)) (1... e6) 2. Nf3 *' },
    { name: 'comments-and-commands', input: '{  A   note  } 1. e4 {[%clk 0:03:12] Good move [%eval 0.4]} {more} e5 ; line note\n2. Nf3 *' },
    { name: 'roster-order-and-extra-headers', input: '[Zed "first"]\n[Black "B"]\n[Opening "Second"]\n[White "A"]\n[Zed "updated"]\n[Event "Night"]\n\n1. e4 *' },
    { name: 'numeric-header-order', input: '[10 "ten"]\n[2 "two"]\n[01 "one"]\n[X "x"]\n[Result "*"]\n\n1. e4 *' },
    { name: 'header-escapes', input: '[Event "The \\"Open\\""]\n[Annotator "A\\\\B"]\n\n1. e4 *' },
    { name: 'empty-fen-and-result', input: '[FEN ""]\n[Result ""]\n\n1. e4 1-0' },
    { name: 'header-result-wins', input: '[Result "1-0"]\n\n1. e4 0-1' },
    { name: 'white-row-break', input: '1. e4 (1. d4 d5) 1... e5 2. Nf3 *' },
    { name: 'black-row-break', input: '1. e4 e5 (1... c5 2. Nf3) (1... e6) 2. Nf3 *' },
    { name: 'white-fen', input: `${kings} w - - 0 1` },
    { name: 'bare-black-fen', input: fen },
    { name: 'promotion', input: '[FEN "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"]\n\n1. a8=N *' },
    { name: 'en-passant', input: '[FEN "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 13"]\n\n13. exd6 *' },
    { name: 'multi-broken-game', input: '[White "A"]\n\n1. e4 e5 1-0\n\n[White "B"]\n\n1. e4 e4 *\n\n[White "C"]\n\n1. d4 *\n' },
    { name: 'no-result-between-games', input: '[White "A"]\n\n1. e4\n[White "B"]\n\n1. d4\n' },
    { name: 'bom-escaped-line', input: '\uFEFF% exporter text\n[Event "A"]\n\n1. e4 *' },
    { name: 'ecmascript-whitespace', input: '{a\uFEFFb\u00A0c}\uFEFF1.e4\u00A0e5\u2028*' },
    { name: 'unicode-wrap', input: `{${'♞😀 '.repeat(11)}} 1. e4 {${'idea 😀 '.repeat(9)}} e5 (1... c5 {${'line '.repeat(18)}}) 2. Nf3 *` },
    { name: 'fools-mate', input: '1. f3 e5 2. g4 Qh4# 0-1' },
    ...['1-0', '0-1', '1/2-1/2', '*'].map((result) => ({ name: `result-${result}`, input: `1. e4 e5 ${result}` })),
    ...['', ' \n', '*', '[Event "Only headers"]', '1. e4',
      '1. e4 (1. d4', '1. e4 ) *', '1. e4 {oops', '1. e4 $x *',
      '$1 1. e4 *', '(1. e4) *', '1. e4 (1. d4 1-0) *', '[White A]\n1. e4',
      '[FEN "bad"]\n\n*', '1. e4 } *', '1. e4 ] *',
    ].map((input, index) => ({ name: `boundary-${index}`, input })),
  ];
  // Every supported word glyph, suffix, and unknown numeric glyph survives.
  for (const symbol of [...Object.values(pgn.NAG_SYMBOLS), '+/=', '=/+', '+/-', '-/+', '+-', '-+', '=+', '+=', '⊙', '△']) {
    inputs.push({ name: `nag-${symbol}`, input: `1. e4 ${symbol} e5 *` });
  }
  for (const suffix of ['!', '?', '!!', '??', '!?', '?!']) {
    inputs.push({ name: `suffix-${suffix}`, input: `1. e4${suffix} e5 $255 *` });
  }
  for (const seed of [1, 42, 2026]) {
    const chess = new Chess();
    const rand = seeded(seed);
    const moves: string[] = [];
    for (let ply = 0; ply < 60 && !chess.isGameOver(); ply++) {
      const legal = chess.moves();
      const san = legal[Math.floor(rand() * legal.length)];
      const number = pgn.moveNumber(chess.fen(), ply === 0);
      moves.push(number ? `${number} ${san}` : san);
      if (ply % 11 === 0) moves.push(`{walk ${ply} [%eval 0.4]} $1`);
      chess.move(san);
    }
    inputs.push({ name: `walk-${seed}`, input: moves.join(' ') + ' *' });
  }
  return inputs;
}

type EditInput =
  | { kind: 'play'; path: number[]; move: string }
  | { kind: 'delete'; path: number[] }
  | { kind: 'promote'; path: number[] }
  | { kind: 'comment'; path: number[]; text: string }
  | { kind: 'headers'; changes: Record<string, string> };

function generatePgnRoundtrip() {
  const cases = pgnInputs().map(({ name, input }) => {
    const parsed = pgn.parsePgnFile(input);
    const written = parsed.games.map(pgn.writePgn);
    return { name, input, parsed, headerNames: parsed.games.map((game) => Object.keys(game.headers)),
      written, reread: written.map(pgn.parsePgnFile), headers: pgn.readHeaders(input),
      tables: parsed.games.map((game) => table.moveTable(game).map((item) => {
        const cell = (value: table.Cell | null) => value ? { path: value.path, san: value.node.san } : null;
        return item.kind === 'row'
          ? { kind: item.kind, number: item.number, white: cell(item.white), black: cell(item.black) }
          : { kind: item.kind, fen: item.fen, alternatives: item.alternatives.map(cell) };
      })) };
  });
  const editInputs: { name: string; input: string; operations: EditInput[] }[] = [
    { name: 'authoring', input: '*', operations: [
      { kind: 'play', path: [], move: 'e2e4' }, { kind: 'play', path: [0], move: 'e7e5' },
      { kind: 'play', path: [0], move: 'c7c5' }, { kind: 'play', path: [0, 1], move: 'g1f3' },
      { kind: 'play', path: [0], move: 'c7c5' }, { kind: 'comment', path: [0, 1], text: '  Sicilian} [%clk 1:00]  ' },
      { kind: 'promote', path: [0, 1, 0] }, { kind: 'delete', path: [0, 1] },
      { kind: 'headers', changes: { Zed: ' first ', White: ' A ', Event: '', FEN: 'bad', SetUp: 'bad', Result: '' } },
    ] },
    { name: 'nested-promotion', input: '1. e4 e5 (1... c5 2. Nf3 (2. c3 d5) d6) 2. Nf3 *', operations: [
      { kind: 'promote', path: [0, 1, 1, 0] }, { kind: 'promote', path: [0, 1, 0, 0] },
      { kind: 'comment', path: [], text: ' a {b} c 😀 ' }, { kind: 'comment', path: [0], text: ' ' },
      { kind: 'delete', path: [] }, { kind: 'delete', path: [0, 0] },
    ] },
    { name: 'illegal-and-invalid-path', input: '1. e4 *', operations: [
      { kind: 'play', path: [], move: 'e2e5' }, { kind: 'comment', path: [4], text: 'fallback note' },
      { kind: 'play', path: [4], move: 'd2d4' }, { kind: 'delete', path: [-1] },
    ] },
  ];
  const edits = editInputs.map(({ name, input, operations }) => {
    let game = pgn.parsePgn(input);
    return { name, input, steps: operations.map((operation) => {
      let path: number[] | null = null;
      let error: string | null = null;
      try {
        if (operation.kind === 'play') ({ game, path } = edit.playMove(game, operation.path, move.uci(operation.move)));
        else if (operation.kind === 'delete') ({ game, path } = edit.deleteFrom(game, operation.path));
        else if (operation.kind === 'promote') ({ game, path } = edit.promoteVariation(game, operation.path));
        else if (operation.kind === 'comment') game = edit.setComment(game, operation.path, operation.text);
        else game = edit.setHeaders(game, operation.changes);
      } catch (failure) { error = (failure as Error).message; }
      return { operation: { ...operation,
        changeNames: operation.kind === 'headers' ? Object.keys(operation.changes) : undefined },
      game, path, error, written: pgn.writePgn(game), headerNames: Object.keys(game.headers) };
    }) };
  });
  const summaryInputs: Record<string, string>[] = [
    { White: 'Carlsen', Black: 'Nakamura', Event: 'Open', Result: '1-0', Date: '2024.03.??', ECO: 'C65' },
    { White: '?', Black: '?', Event: 'Endgame study' }, { Event: '?', Date: '????.??.??', Result: '*' },
    { White: ' \uFEFFMe ', Black: '...', Opening: 'Ruy Lopez', Date: '2024.3.5.extra' },
    { White: 'Magnus Carlsen', Black: 'Hikaru Nakamura', Event: 'Tata Steel', Annotator: 'Darian' },
  ];
  const summaries = summaryInputs.map((headers) => ({ headers, title: summary.gameTitle(headers), subtitle: summary.gameSubtitle(headers),
    queries: ['', 'carlsen tata', 'CARLSEN OPEN', ' \uFEFF ', 'darian', 'me lopez'].map((query) =>
      ({ query, matches: summary.matchesSearch(headers, query) })) }));
  const comments = [null, '', '[%clk 0:03:12] Good move [%eval 0.4]', 'a [%unknown x] b',
    'a\uFEFFb\u00A0c', '[%unclosed', '😀 note\n next'].map((comment) =>
    ({ comment, displayed: summary.displayComment(comment ?? undefined) }));
  const game = (id: string, collectionId: string, position: number): Game =>
    ({ id, collectionId, position, pgn: '*', orientation: 'w', addedAt: 0 });
  const library: Library = { collections: [], puzzles: [], runs: [], attempts: [],
    gameCollections: [{ id: 'b', name: 'B', createdAt: 1 }, { id: 'a', name: 'A', createdAt: 1 }],
    games: [game('y', 'a', 3), game('x', 'a', 0), game('z', 'b', 0), game('t', 'a', 3)] };
  return { version: 1, cases, edits, summaries, comments, library: { input: library,
    collections: gameLibrary.gameCollectionsOf(library), games: gameLibrary.gamesIn(library, 'a'),
    moved: gameLibrary.moveGames(library, library.games, 'b'),
    shifts: library.games.map((game) => ({ id: game.id, up: gameLibrary.shiftGame(library, game, -1),
      down: gameLibrary.shiftGame(library, game, 1) })) } };
}

/** Importers regenerate in memory without writing. */
export function generateFixtures(): Record<string, string> {
  return Object.fromEntries(Object.entries({
    'board.json': generateBoard(), 'content-keys.json': generateContentKeys(),
    'import.json': generateImports(), 'puzzle-model.json': generatePuzzleModel(),
    'pgn-roundtrip.json': generatePgnRoundtrip(),
  }).map(([name, value]) => [name, `${JSON.stringify(value, null, 2)}\n`]));
}

// Importing this module in vitest performs no writes.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const generated = generateFixtures();
  mkdirSync(fixtureDirectory, { recursive: true });
  for (const [name, content] of Object.entries(generated)) {
    writeFileSync(resolve(fixtureDirectory, name), content);
    console.log(`Wrote ${name}`);
  }
  // Fail early if a generated file cannot be read back.
  for (const [name, content] of Object.entries(generated)) {
    if (readFileSync(resolve(fixtureDirectory, name), 'utf8') !== content) {
      throw new Error(`Fixture write failed: ${name}`);
    }
  }
}
