import { Chess } from 'chess.js';
import { makeMove, moveFrom, moveTo, movePromotion, parseUci } from './move';
import type { PromotionPiece, Uci } from './move';
import type { PieceType, Placement, Side } from './puzzle';

/**
 * The only file that knows chess rules.
 *
 * Everything above it — the trie, the runner, the session — works on UCI
 * strings and never asks whether a move is legal. That separation is what makes
 * "an illegal drag is free, a legal move to the wrong square is a mistake" a
 * structural fact rather than a special case, so it is worth keeping strict:
 * nothing else in the app should import chess.js.
 */

export type { PieceType };

export interface Piece {
  square: string;
  type: PieceType;
  color: Side;
}

/** All 64 squares, a1 first, in rank-major order. */
export const SQUARES: string[] = (() => {
  const out: string[] = [];
  for (let rank = 1; rank <= 8; rank++) {
    for (const file of 'abcdefgh') out.push(`${file}${rank}`);
  }
  return out;
})();

export function turnOf(fen: string): Side {
  return new Chess(fen).turn();
}

export function piecesOn(fen: string): Piece[] {
  const out: Piece[] = [];
  for (const row of new Chess(fen).board()) {
    for (const cell of row) {
      if (cell) out.push({ square: cell.square, type: cell.type, color: cell.color });
    }
  }
  return out;
}

export interface Target {
  /** True when landing here requires choosing a promotion piece. */
  promotion: boolean;
  /** True when a piece is captured, so the UI can ring rather than dot it. */
  capture: boolean;
}

/**
 * Legal destinations for the piece on `from`, keyed by destination square.
 *
 * The four promotion moves to one square collapse into a single target flagged
 * `promotion`. The board should offer one place to tap and then ask which
 * piece — offering four identical-looking squares would be unusable.
 */
export function targetsFrom(fen: string, from: string): Map<string, Target> {
  const targets = new Map<string, Target>();
  let moves;
  try {
    moves = new Chess(fen).moves({ square: from as never, verbose: true });
  } catch {
    // chess.js throws on a square with no piece or a malformed square.
    return targets;
  }

  for (const move of moves) {
    const existing = targets.get(move.to);
    const promotion = Boolean(move.promotion);
    const capture = move.flags.includes('c') || move.flags.includes('e');
    if (existing) {
      existing.promotion ||= promotion;
      existing.capture ||= capture;
    } else {
      targets.set(move.to, { promotion, capture });
    }
  }
  return targets;
}

/** Every legal move in the position, as UCI. */
export function legalMoves(fen: string): Uci[] {
  return new Chess(fen)
    .moves({ verbose: true })
    .map((move) => makeMove(move.from, move.to, (move.promotion as PromotionPiece) ?? null));
}

export function isLegal(fen: string, move: Uci): boolean {
  return applyUci(fen, move) !== null;
}

/**
 * The position after `move`, or null if the move is illegal.
 *
 * Returning null rather than throwing is deliberate: an illegal move is an
 * ordinary event here — it is what a mis-drag produces — and it must be cheap
 * and undramatic to handle.
 */
export function applyUci(fen: string, move: Uci): string | null {
  const chess = new Chess(fen);
  try {
    const played = chess.move({
      from: moveFrom(move),
      to: moveTo(move),
      promotion: movePromotion(move) ?? undefined,
    });
    return played ? chess.fen() : null;
  } catch {
    return null;
  }
}

/** SAN for display. Null when the move is illegal in this position. */
export function sanFor(fen: string, move: Uci): string | null {
  const chess = new Chess(fen);
  try {
    const played = chess.move({
      from: moveFrom(move),
      to: moveTo(move),
      promotion: movePromotion(move) ?? undefined,
    });
    return played ? played.san : null;
  } catch {
    return null;
  }
}

/**
 * The position a puzzle is actually solved from.
 *
 * Lichess puzzles store the FEN one ply early with the opponent's move first
 * (see `Puzzle.setupMove`). The UI animates that ply, so the solver's starting
 * position is the one after it. Falls back to the raw FEN if the setup move
 * does not apply, rather than rendering nothing.
 */
export function startingFen(fen: string, setupMove?: Uci): string {
  if (!setupMove) return fen;
  return applyUci(fen, setupMove) ?? fen;
}

/**
 * Whether moving from → to needs a promotion choice, without committing to one.
 * Used to decide whether to open the picker before submitting.
 */
export function needsPromotion(fen: string, from: string, to: string): boolean {
  return targetsFrom(fen, from).get(to)?.promotion ?? false;
}

/** Parses a UCI string and confirms it is legal here. Null if either fails. */
export function legalUci(fen: string, text: string): Uci | null {
  const move = parseUci(text);
  return move && isLegal(fen, move) ? move : null;
}

/**
 * Walks a puzzle's solutions and returns the first move that cannot be played,
 * or null when every line is legal throughout.
 *
 * The importer checks that a FEN is structurally plausible and that moves are
 * well-formed UCI, but neither says the moves are *legal in this position*. A
 * puzzle that fails here is unsolvable: the board will never accept the move,
 * so the hint points at something you cannot play and the session cannot get
 * past it. Cheaper to reject at import than to strand someone mid-session.
 */
export function firstIllegalMove(
  fen: string,
  setupMove: Uci | undefined,
  solutions: Uci[][],
): { move: Uci; ply: number } | null {
  const start = startingFen(fen, setupMove);

  for (const line of solutions) {
    let position = start;
    for (let ply = 0; ply < line.length; ply++) {
      const next = applyUci(position, line[ply]);
      if (!next) return { move: line[ply], ply };
      position = next;
    }
  }
  return null;
}

/** Whether a setup move can actually be played into the stored position. */
export function setupMoveIsLegal(fen: string, setupMove: Uci | undefined): boolean {
  return !setupMove || applyUci(fen, setupMove) !== null;
}

export function pieceAt(fen: string, square: string): Piece | null {
  try {
    const found = new Chess(fen).get(square as never);
    return found ? { square, type: found.type, color: found.color } : null;
  } catch {
    return null;
  }
}

/**
 * The position with a piece added, or null if it cannot be added there.
 *
 * The mirror of `applyUci` for the missing-piece kind, and null for the same
 * undramatic reasons: a tap on an occupied square is an ordinary mis-hit, not
 * an error worth throwing over.
 */
export function withPiece(fen: string, placement: Placement): string | null {
  const rank = placement.square[1];
  // A pawn on the first or last rank is not a position chess.js will refuse to
  // hold, but it is not a position either.
  if (placement.type === 'p' && (rank === '1' || rank === '8')) return null;

  try {
    const chess = new Chess(fen);
    // Adding onto an occupied square would silently replace the piece standing
    // there, which is a different puzzle than the one that was authored.
    if (chess.get(placement.square as never)) return null;
    if (!chess.put({ type: placement.type, color: placement.color }, placement.square as never)) {
      return null;
    }
    const next = chess.fen();
    // `put` will build a position it cannot then load — a second king, a side
    // already to move while the other is in check. Loading it is the check.
    new Chess(next);
    return next;
  } catch {
    return null;
  }
}

/** Squares with nothing on them: the only ones a piece can be added to. */
export function emptySquares(fen: string): string[] {
  try {
    const chess = new Chess(fen);
    return SQUARES.filter((square) => !chess.get(square as never));
  } catch {
    return [];
  }
}

/**
 * Every piece and square that would checkmate the side to move.
 *
 * Used to audit an authored missing-piece puzzle: the answer is one placement,
 * so a position where two different pieces both mate has more than one right
 * answer and will mark a correct one wrong. Kings are not candidates.
 */
export function matingPlacements(fen: string, color: Side): Placement[] {
  const types: PieceType[] = ['q', 'r', 'b', 'n', 'p'];
  const found: Placement[] = [];
  for (const square of emptySquares(fen)) {
    for (const type of types) {
      const placement: Placement = { color, type, square };
      const next = withPiece(fen, placement);
      if (!next) continue;
      try {
        if (new Chess(next).isCheckmate()) found.push(placement);
      } catch {
        // Not a position that loads; not a candidate.
      }
    }
  }
  return found;
}

export interface ReplayStep {
  /** SAN for display, e.g. `Ra8#`. */
  san: string;
  /** UCI, for highlighting the squares. */
  move: Uci;
  /** Position after the move. */
  fen: string;
  /** True when this ply belongs to the solver rather than the opponent. */
  bySolver: boolean;
}

/**
 * Expands a solution line into positions and SAN, for browsing a puzzle.
 *
 * Stops at the first move that will not play rather than throwing, so a
 * detail view can still render — and show how far it got — for a puzzle that
 * predates the import-time legality check.
 */
export function replayLine(fen: string, setupMove: Uci | undefined, line: Uci[]): ReplayStep[] {
  const steps: ReplayStep[] = [];
  let position = startingFen(fen, setupMove);

  for (let ply = 0; ply < line.length; ply++) {
    const move = line[ply];
    const san = sanFor(position, move);
    const next = san ? applyUci(position, move) : null;
    if (!san || !next) break;
    steps.push({ san, move, fen: next, bySolver: ply % 2 === 0 });
    position = next;
  }
  return steps;
}
