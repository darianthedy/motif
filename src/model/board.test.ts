import { describe, expect, it } from 'vitest';
import {
  applyUci,
  isLegal,
  legalMoves,
  needsPromotion,
  piecesOn,
  sanFor,
  SQUARES,
  startingFen,
  targetsFrom,
  turnOf,
} from './board';
import { uci } from './move';

const MATE_FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';
const PROMO_FEN = '4k3/P7/8/8/8/8/8/4K3 w - - 0 1';

describe('board geometry', () => {
  it('enumerates 64 squares starting at a1', () => {
    expect(SQUARES).toHaveLength(64);
    expect(SQUARES[0]).toBe('a1');
    expect(SQUARES[63]).toBe('h8');
  });

  it('reads pieces off a FEN', () => {
    // Black king, three black pawns, white rook, white king.
    const pieces = piecesOn(MATE_FEN);
    expect(pieces).toHaveLength(6);
    expect(pieces).toContainEqual({ square: 'g8', type: 'k', color: 'b' });
    expect(pieces).toContainEqual({ square: 'a1', type: 'r', color: 'w' });
  });

  it('reports the side to move', () => {
    expect(turnOf(MATE_FEN)).toBe('w');
    expect(turnOf('6k1/5ppp/8/8/8/8/8/R5K1 b - - 0 1')).toBe('b');
  });
});

describe('legal destinations', () => {
  it('lists targets for a piece', () => {
    const targets = targetsFrom(MATE_FEN, 'a1');
    expect(targets.has('a8')).toBe(true);
    expect(targets.has('b1')).toBe(true);
    expect(targets.has('b2'), 'rooks do not move diagonally').toBe(false);
  });

  it('returns nothing for an empty square instead of throwing', () => {
    expect(targetsFrom(MATE_FEN, 'd4').size).toBe(0);
    expect(targetsFrom(MATE_FEN, 'zz').size).toBe(0);
  });

  it('collapses the four promotion moves into one target', () => {
    const targets = targetsFrom(PROMO_FEN, 'a7');
    expect(targets.get('a8')).toEqual({ promotion: true, capture: false });
    expect(needsPromotion(PROMO_FEN, 'a7', 'a8')).toBe(true);
  });

  it('flags captures so the UI can ring rather than dot them', () => {
    const fen = '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1';
    const targets = targetsFrom(fen, 'e4');
    expect(targets.get('d5')).toMatchObject({ capture: true });
    expect(targets.get('e5')).toMatchObject({ capture: false });
  });

  it('does not offer moves that leave the king in check', () => {
    // The rook is pinned against its own king by the black queen.
    const pinned = '4k3/8/8/8/8/4q3/4R3/4K3 w - - 0 1';
    const targets = targetsFrom(pinned, 'e2');
    expect(targets.has('a2'), 'stepping off the file exposes the king').toBe(false);
    expect(targets.has('e3'), 'capturing the pinner is fine').toBe(true);
  });
});

describe('applying moves', () => {
  it('returns the resulting position', () => {
    const after = applyUci(MATE_FEN, uci('a1a8'));
    expect(after).toContain('R5k1');
    expect(after).toContain(' b ');
  });

  it('returns null for an illegal move rather than throwing', () => {
    expect(applyUci(MATE_FEN, uci('a1b2'))).toBeNull();
    expect(applyUci(MATE_FEN, uci('d4d5')), 'no piece there').toBeNull();
    expect(isLegal(MATE_FEN, uci('a1b2'))).toBe(false);
  });

  it('honours the promotion piece', () => {
    expect(applyUci(PROMO_FEN, uci('a7a8q'))).toContain('Q3k3');
    expect(applyUci(PROMO_FEN, uci('a7a8n'))).toContain('N3k3');
  });

  it('renders SAN for display', () => {
    expect(sanFor(MATE_FEN, uci('a1a8'))).toBe('Ra8#');
    // A knight on a8 does not attack e8, so this promotion gives no check.
    expect(sanFor(PROMO_FEN, uci('a7a8n'))).toBe('a8=N');
    expect(sanFor(PROMO_FEN, uci('a7a8q')), 'a queen on a8 does').toBe('a8=Q+');
    expect(sanFor(MATE_FEN, uci('a1b2'))).toBeNull();
  });

  it('enumerates every legal move as UCI, promotions included', () => {
    const moves = legalMoves(PROMO_FEN);
    expect(moves).toContain('a7a8q');
    expect(moves).toContain('a7a8n');
  });
});

describe('puzzle start position', () => {
  it('plays the setup move in', () => {
    const start = startingFen(MATE_FEN, uci('a1a8'));
    expect(start).toContain('R5k1');
    expect(turnOf(start)).toBe('b');
  });

  it('falls back to the raw FEN when the setup move does not apply', () => {
    expect(startingFen(MATE_FEN, uci('h1h8'))).toBe(MATE_FEN);
  });

  it('is a no-op without a setup move', () => {
    expect(startingFen(MATE_FEN)).toBe(MATE_FEN);
  });
});
