import { DEFAULT_POSITION } from 'chess.js';
import { describe, expect, it } from 'vitest';
import { newGame, parsePgn, parsePgnFile, readHeaders, writePgn } from './pgn';
import type { MoveNode } from './pgn';

const sans = (list: MoveNode[]) => list.map((node) => node.san);

function mainNodes(list: MoveNode[]): MoveNode[] {
  const out: MoveNode[] = [];
  while (list.length) {
    out.push(list[0]);
    list = list[0].children;
  }
  return out;
}

/** The main line, as SAN. */
const mainLine = (list: MoveNode[]) => sans(mainNodes(list));

const ANNOTATED = `[Event "Club night"]
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

describe('reading PGN', () => {
  it('keeps headers, the main line, variations, comments and annotations', () => {
    const game = parsePgn(ANNOTATED);
    expect(game.headers).toMatchObject({ Event: 'Club night', White: 'Me', Result: '1-0' });
    expect(game.comment).toBe('An old favourite.');
    expect(mainLine(game.moves)).toEqual(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6']);

    const e4 = game.moves[0];
    expect(sans(e4.children)).toEqual(['e5', 'c5']);
    const c5 = e4.children[1];
    expect(c5.comment).toBe('Sicilian');
    expect(sans(c5.children)).toEqual(['Nf3', 'c3']);
    expect(sans(c5.children[0].children)).toEqual(['d6']);

    const nf3 = e4.children[0].children[0];
    expect(nf3.nags).toEqual([1]);
    const bb5 = nf3.children[0].children[0];
    expect(bb5.nags).toEqual([1]);
    expect(bb5.uci).toBe('f1b5');
    expect(sans(bb5.children)).toEqual(['a6', 'Nf6']);
    expect(bb5.children[0].children[0].comment).toBe('to the end of the line');
  });

  it('round-trips through the writer', () => {
    const game = parsePgn(ANNOTATED);
    const written = writePgn(game);
    expect(parsePgn(written)).toEqual(game);
    expect(writePgn(parsePgn(written))).toBe(written);
  });

  it('numbers Black’s move after anything that comes between it and White’s', () => {
    const written = writePgn(parsePgn(ANNOTATED));
    const movetext = written.replace(/\s+/g, ' ');
    expect(movetext).toContain('{An old favourite.} 1. e4 e5 (1... c5 {Sicilian} 2. Nf3 (2. c3) 2... d6)');
    expect(movetext).toContain('2. Nf3 $1 Nc6 3. Bb5 $1 a6 (3... Nf6 4. O-O) 4. Ba4');
    expect(written.trimEnd().endsWith('1-0')).toBe(true);
    expect(written.split('\n').every((line) => line.length <= 80)).toBe(true);
  });

  it('starts from a FEN header, with Black to move', () => {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 30';
    const game = parsePgn(`[SetUp "1"]\n[FEN "${fen}"]\n\n30... h6 31. Ra8+ Kh7 *`);
    expect(game.startFen).toBe(fen);
    expect(mainLine(game.moves)).toEqual(['h6', 'Ra8+', 'Kh7']);
    expect(writePgn(game)).toContain('30... h6 31. Ra8+ Kh7 *');
  });

  it('keeps a comment before the first move of a variation', () => {
    const game = parsePgn('1. e4 ({or} 1. d4 d5) e5 *');
    expect(game.moves[1].before).toBe('or');
    expect(writePgn(game)).toContain('1. e4 ({or} 1. d4 d5) 1... e5 *');
  });

  it('reads loosely written moves', () => {
    const game = parsePgn('1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.0-0 Nf6!? *');
    expect(mainLine(game.moves)).toEqual(['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'O-O', 'Nf6']);
    expect(mainNodes(game.moves)[7].nags).toEqual([5]);
  });

  it('reads annotation symbols written as words, as Chess.com exports them', () => {
    const game = parsePgn('1. e4 e5 = 2. Nf3 ⩱ (2. Qh5 ⨀) Nc6 +/- 3. Bb5 -+ *');
    const [e4, e5, nf3, nc6, bb5] = mainNodes(game.moves);
    expect([e4.nags, e5.nags, nf3.nags, nc6.nags, bb5.nags]).toEqual([[], [10], [15], [16], [19]]);
    expect(e5.children[1].nags).toEqual([22]);
    // Written back the standard way.
    expect(writePgn(game).replace(/\s+/g, ' ')).toContain('1. e4 e5 $10 2. Nf3 $15 (2. Qh5 $22) 2... Nc6 $16');
  });

  it('takes the result from the movetext when there is no header for it', () => {
    expect(parsePgn('1. f3 e5 2. g4 Qh4# 0-1').headers.Result).toBe('0-1');
    expect(parsePgn('1. e4').headers.Result).toBe('*');
  });

  it('reads a bare FEN as a game with no moves', () => {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';
    const { games, errors } = parsePgnFile(`  ${fen}\n`);
    expect(errors).toEqual([]);
    expect(games).toHaveLength(1);
    expect(games[0].startFen).toBe(fen);
    expect(games[0].moves).toEqual([]);
    expect(games[0].headers.FEN).toBe(fen);
  });
});

describe('reading a file of games', () => {
  it('splits games, and skips one with an illegal move', () => {
    const file = `[White "A"]\n\n1. e4 e5 1-0\n\n[White "B"]\n\n1. e4 e4 *\n\n[White "C"]\n\n1. d4 *\n`;
    const { games, errors } = parsePgnFile(file);
    expect(games.map((g) => g.headers.White)).toEqual(['A', 'C']);
    expect(errors).toEqual([{ game: 2, message: '1... e4 is not a legal move' }]);
  });

  it('splits games written without a result between them', () => {
    const { games } = parsePgnFile(`[White "A"]\n\n1. e4\n[White "B"]\n\n1. d4\n`);
    expect(games.map((g) => mainLine(g.moves))).toEqual([['e4'], ['d4']]);
  });

  it('reports unbalanced variations and unclosed comments', () => {
    expect(parsePgnFile('1. e4 (1. d4').errors[0].message).toMatch(/never closed/);
    expect(parsePgnFile('1. e4 ) *').errors[0].message).toMatch(/no \(/);
    expect(parsePgnFile('1. e4 {oops').errors[0].message).toMatch(/never closed/);
  });

  it('reads an empty file as no games', () => {
    expect(parsePgnFile('  \n')).toEqual({ games: [], errors: [] });
  });
});

describe('a new game', () => {
  it('has the seven headers and the starting position', () => {
    const game = newGame();
    expect(Object.keys(game.headers)).toEqual(['Event', 'Site', 'Date', 'Round', 'White', 'Black', 'Result']);
    expect(game.startFen).toBe(DEFAULT_POSITION);
    expect(parsePgn(writePgn(game))).toEqual(game);
  });

  it('records a set-up position in its headers', () => {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';
    const game = newGame(fen);
    expect(game.headers).toMatchObject({ SetUp: '1', FEN: fen });
    expect(parsePgn(writePgn(game))).toEqual(game);
  });

  it('escapes quotes in headers and braces in comments', () => {
    const game = { ...newGame(), comment: 'a {b} c' };
    game.headers.Event = 'The "Open"';
    const read = parsePgn(writePgn(game));
    expect(read.headers.Event).toBe('The "Open"');
    expect(read.comment).toBe('a {b) c');
  });
});

describe('reading only the headers', () => {
  it('reads the leading block, and nothing after it', () => {
    const pgn = writePgn(parsePgn(ANNOTATED));
    expect(readHeaders(pgn)).toEqual(parsePgn(ANNOTATED).headers);
    expect(readHeaders('[White "A \\"B\\""]\n\n1. e4 [x "y"] *')).toEqual({ White: 'A "B"' });
    expect(readHeaders('1. e4 *')).toEqual({});
  });
});
