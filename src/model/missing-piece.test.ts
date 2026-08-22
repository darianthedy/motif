import { describe, expect, it } from 'vitest';
import { matingPlacements, pieceAt, withPiece } from './board';
import { importJson } from './import/json';
import { uci } from './move';
import {
  contentKey,
  isMissingPiece,
  parsePlacement,
  placementText,
  solverSide,
} from './puzzle';
import type { Placement, Puzzle } from './puzzle';
import { MissingPieceRunner, ATTEMPTS_BEFORE_HINT } from './runner';
import { parseState } from './storage';

/**
 * The archetype: Black to move, and a white knight on g6 is mate. The h-pawn
 * cannot take it because the rook on h1 pins it to the king — which is why the
 * position needs the pin as well as the hole.
 */
const SAMPLE_FEN = '6rk/6pp/8/1p1b4/p7/3P4/PPP5/1K5R b - - 0 1';
const KNIGHT: Placement = { color: 'w', type: 'n', square: 'g6' };

function puzzle(overrides: Partial<Puzzle> = {}): Puzzle {
  return {
    id: 'p1',
    fen: SAMPLE_FEN,
    solutions: [],
    addPiece: KNIGHT,
    tags: [],
    addedAt: 0,
    ...overrides,
  };
}

describe('placement notation', () => {
  it('reads the colour off the case, as a FEN does', () => {
    expect(parsePlacement('Ng6')).toEqual({ color: 'w', type: 'n', square: 'g6' });
    expect(parsePlacement('ng6')).toEqual({ color: 'b', type: 'n', square: 'g6' });
    expect(parsePlacement('  Q f8 ')).toEqual({ color: 'w', type: 'q', square: 'f8' });
  });

  it('accepts an explicit colour, for anyone in the habit of writing SAN', () => {
    expect(parsePlacement('bNg6')).toEqual({ color: 'b', type: 'n', square: 'g6' });
    expect(parsePlacement('wng6')).toEqual({ color: 'w', type: 'n', square: 'g6' });
    // The one genuinely ambiguous letter: a bare `b` is a bishop, not a colour.
    expect(parsePlacement('bg6')).toEqual({ color: 'b', type: 'b', square: 'g6' });
    expect(parsePlacement('bBg6')).toEqual({ color: 'b', type: 'b', square: 'g6' });
  });

  it('rejects anything else', () => {
    for (const bad of ['', 'g6', 'Xg6', 'Ng9', 'Nj6', 'Ng6g7', 'knight g6']) {
      expect(parsePlacement(bad), bad).toBeNull();
    }
  });

  it('round-trips through its written form', () => {
    for (const text of ['Ng6', 'ng6', 'Qf8', 'pa2']) {
      expect(placementText(parsePlacement(text)!)).toBe(text);
    }
  });
});

describe('adding a piece to a position', () => {
  it('puts the piece on the square', () => {
    const next = withPiece(SAMPLE_FEN, KNIGHT)!;
    expect(pieceAt(next, 'g6')).toEqual({ square: 'g6', type: 'n', color: 'w' });
    // Everything else is where it was, and it is still Black to move.
    expect(next.split(' ')[1]).toBe('b');
  });

  it('refuses a square that is taken, rather than replacing what stands there', () => {
    expect(withPiece(SAMPLE_FEN, { color: 'w', type: 'n', square: 'g7' })).toBeNull();
  });

  it('refuses positions that are not positions', () => {
    expect(withPiece(SAMPLE_FEN, { color: 'w', type: 'p', square: 'e8' }), 'pawn on the 8th').toBeNull();
    expect(withPiece(SAMPLE_FEN, { color: 'w', type: 'k', square: 'e4' }), 'second king').toBeNull();
  });

  it('finds the one piece that mates, which is what makes the puzzle fair', () => {
    // If two placements mated, one of them would be marked wrong.
    expect(matingPlacements(SAMPLE_FEN, 'w').map(placementText)).toEqual(['Ng6']);
  });
});

describe('missing-piece identity', () => {
  it('is the kind, derived rather than declared', () => {
    expect(isMissingPiece(puzzle())).toBe(true);
    expect(isMissingPiece({ addPiece: undefined })).toBe(false);
  });

  it('separates two puzzles that differ only in the answer', () => {
    const a = puzzle();
    const b = puzzle({ addPiece: { color: 'w', type: 'q', square: 'g6' } });
    expect(contentKey(a)).not.toBe(contentKey(b));
  });

  it('leaves the key of an ordinary puzzle untouched', () => {
    const moves: Puzzle = {
      id: 'p2',
      fen: SAMPLE_FEN,
      solutions: [[uci('g8g7')]],
      tags: [],
      addedAt: 0,
    };
    expect(contentKey(moves)).toBe(`${SAMPLE_FEN.split(' ').slice(0, 4).join(' ')}/-/g8g7`);
  });

  it('is answered for the colour of the piece, not for the side to move', () => {
    // Black is to move in the sample; the answer is a white knight.
    expect(solverSide(puzzle())).toBe('w');
  });
});

describe('running a missing-piece puzzle', () => {
  it('solves on the right piece and the right square', () => {
    const runner = new MissingPieceRunner(puzzle(), KNIGHT);
    expect(runner.submit('g6', 'n')).toEqual({ kind: 'correct' });
    expect(runner.complete).toBe(true);
    expect(runner.result).toBe('solved');
  });

  it('counts the right square with the wrong piece as a miss', () => {
    const runner = new MissingPieceRunner(puzzle(), KNIGHT);
    expect(runner.submit('g6', 'q')).toEqual({ kind: 'wrong' });
    expect(runner.submit('f6', 'n'), 'and the right piece on the wrong square').toEqual({
      kind: 'wrong',
    });
    expect(runner.mistakes).toBe(2);
    expect(runner.complete).toBe(false);

    // Getting there in the end still counts as having got it wrong.
    runner.submit('g6', 'n');
    expect(runner.result).toBe('failed');
  });

  it('reveals the answer after the same three tries a move puzzle allows', () => {
    const runner = new MissingPieceRunner(puzzle(), KNIGHT);
    for (let i = 0; i < ATTEMPTS_BEFORE_HINT - 1; i++) runner.submit('a3', 'q');
    expect(runner.shouldRevealHint).toBe(false);
    expect(runner.revealHint()).toBeNull();
    expect(runner.hinted, 'peeking early does not mark the run').toBe(false);

    runner.submit('a3', 'q');
    expect(runner.shouldRevealHint).toBe(true);
    expect(runner.revealHint()).toEqual(KNIGHT);
    expect(runner.hinted).toBe(true);
  });
});

describe('importing missing-piece puzzles', () => {
  const file = (entry: string) => `{ "puzzles": [ ${entry} ] }`;

  it('reads the format as written', () => {
    const result = importJson(
      file(`{ "id": 187, "fen": "${SAMPLE_FEN}", "solutions": [],
              "tags": ["missingPiece"], "comment": "Add a knight and it's mate",
              "add_piece": "Ng6" }`),
    );
    expect(result.rejected).toEqual([]);
    expect(result.inserted).toHaveLength(1);
    expect(result.inserted[0]).toMatchObject({
      solutions: [],
      addPiece: KNIGHT,
      sourceId: '187',
      comment: "Add a knight and it's mate",
    });
  });

  it('rejects a placement that cannot be made', () => {
    const cases: [string, RegExp][] = [
      ['"add_piece": "Kg6"', /king cannot be added/],
      ['"add_piece": "Ng7"', /g7 is not empty/],
      ['"add_piece": "Pg1"', /does not make a legal position/],
      ['"add_piece": "knight to g6"', /Malformed piece/],
      ['"add_piece": 7', /Malformed piece/],
    ];
    for (const [field, reason] of cases) {
      const result = importJson(file(`{ "fen": "${SAMPLE_FEN}", "solutions": [], ${field} }`));
      expect(result.inserted, field).toHaveLength(0);
      expect(result.rejected[0].reason, field).toMatch(reason);
    }
  });

  it('refuses to be both kinds at once', () => {
    const result = importJson(
      file(`{ "fen": "${SAMPLE_FEN}", "solutions": [["g8g7"]], "add_piece": "Ng6" }`),
    );
    expect(result.rejected[0].reason).toMatch(/can carry no solution/);
  });

  it('still wants a solution from an ordinary puzzle', () => {
    const result = importJson(file(`{ "fen": "${SAMPLE_FEN}", "solutions": [] }`));
    expect(result.rejected[0].reason).toBe('Puzzle has no solution');
  });

  it('imports the sample file whole', async () => {
    const text = await import('../../samples/missing-piece.json?raw').then((m) => m.default);
    const result = importJson(text);
    expect(result.rejected).toEqual([]);
    expect(result.inserted).toHaveLength(3);
    expect(result.collectionName).toBe('Missing pieces');
    // Every answer is the only mate available, so no correct answer is refused.
    for (const entry of result.inserted) {
      const placement = entry.addPiece!;
      expect(matingPlacements(entry.fen, placement.color).map(placementText)).toEqual([
        placementText(placement),
      ]);
    }
  });
});

describe('storing missing-piece puzzles', () => {
  it('survives a round trip, solutions or not', () => {
    const stored = parseState({
      version: 1,
      puzzles: { p1: puzzle(), p2: { ...puzzle({ id: 'p2' }), addPiece: 'ng3' } },
      collections: [],
      progress: {},
      sessions: {},
      recent: [],
    });
    expect(stored.puzzles.p1.addPiece).toEqual(KNIGHT);
    // A hand-edited file may carry the written form rather than the object.
    expect(stored.puzzles.p2.addPiece).toEqual({ color: 'b', type: 'n', square: 'g3' });
  });

  it('still drops a puzzle with neither a solution nor a piece', () => {
    const stored = parseState({
      version: 1,
      puzzles: { p1: { ...puzzle(), addPiece: undefined } },
      collections: [],
      progress: {},
      sessions: {},
      recent: [],
    });
    expect(stored.puzzles.p1).toBeUndefined();
  });
});
