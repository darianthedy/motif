import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess, DEFAULT_POSITION, validateFen } from 'chess.js';
import * as board from '../src/model/board';
import * as move from '../src/model/move';
import type { Placement } from '../src/model/puzzle';

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

/** Add the P03/P04 generators here; importers can regenerate without writing. */
export function generateFixtures(): Record<string, string> {
  return { 'board.json': `${JSON.stringify(generateBoard(), null, 2)}\n` };
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
