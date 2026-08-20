import { describe, expect, it } from 'vitest';
import { parseUci, stripQueenPromotion, uci } from './move';
import { PuzzleRunner } from './runner';
import type { Puzzle } from './puzzle';
import { contentKey, solverSide } from './puzzle';

const MATE_FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';

function puzzle(solutions: string[][], overrides: Partial<Puzzle> = {}): Puzzle {
  return {
    id: 'p1',
    fen: MATE_FEN,
    solutions: solutions.map((line) => line.map(uci)),
    tags: [],
    addedAt: 0,
    ...overrides,
  };
}

describe('UCI parsing', () => {
  it('accepts well-formed moves and lowercases them', () => {
    expect(parseUci('e2e4')).toBe('e2e4');
    expect(parseUci('E7E8Q')).toBe('e7e8q');
    expect(parseUci('  a2a1n ')).toBe('a2a1n');
  });

  it('rejects garbage', () => {
    for (const bad of ['', 'e2', 'e2e9', 'j2j4', 'e7e8k', 'e2e4qq', 'nonsense']) {
      expect(parseUci(bad), bad).toBeNull();
    }
  });

  it('strips only queen promotions', () => {
    expect(stripQueenPromotion(uci('e7e8q'))).toBe('e7e8');
    expect(stripQueenPromotion(uci('e7e8n'))).toBeNull();
    expect(stripQueenPromotion(uci('e2e4'))).toBeNull();
  });
});

describe('solution matching', () => {
  it('accepts the only line', () => {
    const runner = new PuzzleRunner(puzzle([['a1a8']]));
    expect(runner.submit(uci('a1a8'))).toEqual({ kind: 'correct', reply: null, finished: true });
    expect(runner.complete).toBe(true);
    expect(runner.result).toBe('solved');
  });

  it('rejects a wrong move and stays on the same ply', () => {
    const runner = new PuzzleRunner(puzzle([['a1a8']]));
    expect(runner.submit(uci('a1a7'))).toEqual({ kind: 'wrong' });
    expect(runner.mistakes).toBe(1);
    expect(runner.complete).toBe(false);

    expect(runner.submit(uci('a1a8'))).toEqual({ kind: 'correct', reply: null, finished: true });
    expect(runner.result).toBe('failed');
  });

  it('plays the scripted reply between solver moves', () => {
    const runner = new PuzzleRunner(puzzle([['d1h5', 'g7g6', 'h5g6']]));
    expect(runner.submit(uci('d1h5'))).toEqual({ kind: 'correct', reply: 'g7g6', finished: false });
    expect(runner.submit(uci('h5g6'))).toEqual({ kind: 'correct', reply: null, finished: true });
    expect(runner.result).toBe('solved');
  });

  it('accepts either of two solutions from the start', () => {
    const p = puzzle([['a1a8'], ['a1b1']]);
    for (const move of ['a1a8', 'a1b1']) {
      expect(new PuzzleRunner(p).submit(uci(move)).kind).toBe('correct');
    }
  });

  it('merges shared prefixes and diverges later', () => {
    const p = puzzle([
      ['d1h5', 'g7g6', 'h5g6'],
      ['d1h5', 'g7g6', 'h5e8'],
    ]);
    for (const finisher of ['h5g6', 'h5e8']) {
      const runner = new PuzzleRunner(p);
      expect(runner.submit(uci('d1h5'))).toEqual({ kind: 'correct', reply: 'g7g6', finished: false });
      expect(runner.submit(uci(finisher))).toEqual({ kind: 'correct', reply: null, finished: true });
      expect(runner.result).toBe('solved');
    }
  });

  it('keeps each divergent line’s own opponent reply', () => {
    const p = puzzle([
      ['a1a8', 'g8g7', 'a8a7'],
      ['a1b1', 'g8f8', 'b1b8'],
    ]);
    expect(new PuzzleRunner(p).submit(uci('a1a8'))).toMatchObject({ reply: 'g8g7' });
    expect(new PuzzleRunner(p).submit(uci('a1b1'))).toMatchObject({ reply: 'g8f8' });
  });

  it('matches a queening written without the piece', () => {
    const runner = new PuzzleRunner(puzzle([['e7e8']]));
    expect(runner.submit(uci('e7e8q')).kind).toBe('correct');
  });

  it('does not let an underpromotion satisfy a line expecting a queen', () => {
    expect(new PuzzleRunner(puzzle([['e7e8']])).submit(uci('e7e8n'))).toEqual({ kind: 'wrong' });
  });

  it('requires the exact piece for underpromotion puzzles', () => {
    const runner = new PuzzleRunner(puzzle([['e7e8n']]));
    expect(runner.submit(uci('e7e8q'))).toEqual({ kind: 'wrong' });
    expect(runner.submit(uci('e7e8n')).kind).toBe('correct');
  });

  it('refuses submissions after the line ends without recording a mistake', () => {
    const runner = new PuzzleRunner(puzzle([['a1a8']]));
    runner.submit(uci('a1a8'));
    expect(runner.submit(uci('a8a7'))).toEqual({ kind: 'wrong' });
    expect(runner.mistakes).toBe(0);
  });

  it('reports the other accepted first moves for disclosure', () => {
    const runner = new PuzzleRunner(puzzle([['a1a8'], ['a1b1']]));
    runner.submit(uci('a1a8'));
    expect(runner.otherFirstMoves).toEqual(['a1b1']);
  });
});

describe('hints and the retry budget', () => {
  it('reveals only after three wrong tries', () => {
    const runner = new PuzzleRunner(puzzle([['a1a8']]));
    for (let attempt = 1; attempt <= 2; attempt++) {
      runner.submit(uci('a1a7'));
      expect(runner.shouldRevealHint, `after ${attempt}`).toBe(false);
      expect(runner.revealHint()).toBeNull();
    }
    runner.submit(uci('a1a6'));
    expect(runner.shouldRevealHint).toBe(true);
    expect(runner.revealHint()).toBe('a1a8');
    expect(runner.hinted).toBe(true);
  });

  it('budgets per ply, not per puzzle', () => {
    const runner = new PuzzleRunner(puzzle([['d1h5', 'g7g6', 'h5g6']]));
    runner.submit(uci('d1h4'));
    runner.submit(uci('d1h3'));
    expect(runner.wrongAtThisPly).toBe(2);

    runner.submit(uci('d1h5'));
    expect(runner.wrongAtThisPly).toBe(0);
    expect(runner.mistakes).toBe(2);

    runner.submit(uci('h5h6'));
    expect(runner.shouldRevealHint).toBe(false);
  });

  it('hints with the earliest declared line', () => {
    const runner = new PuzzleRunner(puzzle([['a1a8'], ['a1b1']]));
    for (let i = 0; i < 3; i++) runner.submit(uci('a1a7'));
    expect(runner.revealHint()).toBe('a1a8');
  });

  it('does not mark the run hinted just for peeking', () => {
    const runner = new PuzzleRunner(puzzle([['a1a8']]));
    expect(runner.expectedMove).toBe('a1a8');
    expect(runner.hinted).toBe(false);
  });

  it('flags a puzzle with no solutions rather than trapping the session', () => {
    expect(new PuzzleRunner(puzzle([])).degenerate).toBe(true);
  });
});

describe('puzzle identity', () => {
  it('ignores move counters and solution order', () => {
    const a = { fen: MATE_FEN, solutions: [[uci('a1a8')], [uci('a1b1')]] };
    const b = { fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 9 42', solutions: [[uci('a1b1')], [uci('a1a8')]] };
    expect(contentKey(a)).toBe(contentKey(b));
  });

  it('treats a different setup move as a different puzzle', () => {
    const base = { fen: MATE_FEN, solutions: [[uci('a1a8')]] };
    expect(contentKey(base)).not.toBe(contentKey({ ...base, setupMove: uci('g1h1') }));
  });

  it('flips the solver side when a setup move is played in', () => {
    expect(solverSide({ fen: MATE_FEN })).toBe('w');
    expect(solverSide({ fen: MATE_FEN, setupMove: uci('g1h1') })).toBe('b');
  });
});
