import { describe, expect, it } from 'vitest';
import { uci } from '../move';
import {
  deleteFrom,
  fenAt,
  forward,
  lineTo,
  nodeAt,
  onMainLine,
  playMove,
  promoteVariation,
  setComment,
  setHeaders,
  validPath,
} from './edit';
import { newGame, parsePgn, writePgn } from './pgn';

const sanLine = (game: ReturnType<typeof parsePgn>, path: number[]) =>
  lineTo(game, path).map((node) => node.san);

describe('finding your way round a game', () => {
  const game = parsePgn('1. e4 e5 (1... c5 2. Nf3) 2. Nf3 *');

  it('follows a path into a variation', () => {
    expect(sanLine(game, [0, 1, 0])).toEqual(['e4', 'c5', 'Nf3']);
    expect(nodeAt(game, [])).toBeUndefined();
    expect(fenAt(game, [])).toBe(game.startFen);
    expect(fenAt(game, [0])).toBe(game.moves[0].fen);
  });

  it('tells a path that leads nowhere', () => {
    expect(validPath(game, [0, 1, 0])).toBe(true);
    expect(validPath(game, [0, 2])).toBe(false);
  });

  it('steps forward along the main line, to its end', () => {
    expect(forward(game, [])).toEqual([0]);
    expect(forward(game, [0, 1])).toEqual([0, 1, 0]);
    expect(forward(game, [0, 0, 0])).toBeNull();
  });

  it('knows the main line', () => {
    expect(onMainLine([0, 0, 0])).toBe(true);
    expect(onMainLine([0, 1, 0])).toBe(false);
  });
});

describe('playing moves into a game', () => {
  it('carries the line on at its end', () => {
    const start = newGame();
    const first = playMove(start, [], uci('e2e4'));
    const second = playMove(first.game, first.path, uci('e7e5'));
    expect(second.path).toEqual([0, 0]);
    expect(sanLine(second.game, second.path)).toEqual(['e4', 'e5']);
    expect(start.moves).toEqual([]);
  });

  it('starts a variation in the middle of one', () => {
    const game = parsePgn('1. e4 e5 2. Nf3 *');
    const { game: next, path } = playMove(game, [0], uci('c7c5'));
    expect(path).toEqual([0, 1]);
    expect(writePgn(next)).toContain('1. e4 e5 (1... c5) 2. Nf3 *');
  });

  it('goes to a move that is already there rather than adding it twice', () => {
    const game = parsePgn('1. e4 e5 (1... c5) *');
    const result = playMove(game, [0], uci('c7c5'));
    expect(result.path).toEqual([0, 1]);
    expect(result.game).toBe(game);
  });

  it('refuses an illegal move', () => {
    expect(() => playMove(newGame(), [], uci('e2e5'))).toThrow(/not a legal move/);
  });
});

describe('changing a game', () => {
  it('deletes a move and what follows it', () => {
    const game = parsePgn('1. e4 e5 (1... c5 2. Nf3) 2. Nf3 *');
    const { game: next, path } = deleteFrom(game, [0, 1]);
    expect(path).toEqual([0]);
    expect(writePgn(next)).toContain('1. e4 e5 2. Nf3 *');
  });

  it('promotes a variation where it branches off', () => {
    const game = parsePgn('1. e4 e5 (1... c5 2. Nf3 d6) 2. Nf3 *');
    const { game: next, path } = promoteVariation(game, [0, 1, 0, 0]);
    expect(path).toEqual([0, 0, 0, 0]);
    expect(writePgn(next)).toContain('1. e4 c5 (1... e5 2. Nf3) 2. Nf3 d6 *');
  });

  it('leaves the main line as it is', () => {
    const game = parsePgn('1. e4 e5 *');
    expect(promoteVariation(game, [0, 0]).game).toBe(game);
  });

  it('sets and clears a move’s comment, and the game’s', () => {
    let game = parsePgn('1. e4 *');
    game = setComment(game, [0], '  best by test} ');
    expect(game.moves[0].comment).toBe('best by test');
    game = setComment(game, [], 'A note');
    expect(game.comment).toBe('A note');
    game = setComment(game, [0], ' ');
    expect('comment' in game.moves[0]).toBe(false);
    expect(parsePgn(writePgn(game))).toEqual(game);
  });

  it('sets and removes headers, but never the starting position', () => {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';
    let game = newGame(fen);
    game = setHeaders(game, { White: ' Me ', Event: '', FEN: 'nonsense', Result: '' });
    expect(game.headers.White).toBe('Me');
    expect('Event' in game.headers).toBe(false);
    expect(game.headers.FEN).toBe(fen);
    expect(game.headers.Result).toBe('*');
  });
});
