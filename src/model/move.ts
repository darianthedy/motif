/**
 * Moves, in long algebraic (UCI) form.
 *
 * Deliberately a plain string rather than a `{from, to, promotion}` object.
 * Moves are compared constantly — every tap runs a trie lookup — and strings
 * are the only thing JavaScript compares and keys a `Map` by *value*. An object
 * would need serializing at every lookup anyway, so the string is the honest
 * representation and the object is the derived one.
 *
 * SAN stays out of the model entirely: rendering it needs a board and parsing
 * it needs disambiguation rules, neither of which belong in a hot path. The UI
 * converts for display via chess.js.
 */

/** A validated UCI move: `e2e4`, `e7e8q`. */
export type Uci = string & { readonly __uci: unique symbol };

export type PromotionPiece = 'q' | 'r' | 'b' | 'n';

const UCI_RE = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

/** Validates and normalizes a UCI string. Returns null for anything else. */
export function parseUci(text: string): Uci | null {
  const lower = text.trim().toLowerCase();
  return UCI_RE.test(lower) ? (lower as Uci) : null;
}

/** Throws on bad input. For literals in tests and seed data, not for imports. */
export function uci(text: string): Uci {
  const move = parseUci(text);
  if (!move) throw new Error(`Not a UCI move: ${text}`);
  return move;
}

export function moveFrom(move: Uci): string {
  return move.slice(0, 2);
}

export function moveTo(move: Uci): string {
  return move.slice(2, 4);
}

export function movePromotion(move: Uci): PromotionPiece | null {
  return move.length === 5 ? (move[4] as PromotionPiece) : null;
}

export function makeMove(from: string, to: string, promotion?: PromotionPiece | null): Uci {
  return uci(`${from}${to}${promotion ?? ''}`);
}

/**
 * The same move with an explicit queen promotion removed, or null if there is
 * nothing to remove.
 *
 * Source data routinely writes a queening as plain `e7e8`, since omitting the
 * piece conventionally means queen. The model has no board and so cannot tell
 * at import time whether `e7e8` is a pawn promoting or a king stepping up,
 * which rules out normalizing on the way in. The trie resolves it on the way
 * out instead: a submitted `e7e8q` that misses retries as `e7e8`.
 *
 * An underpromotion carries `n`/`r`/`b`, never takes this path, and so still
 * fails against a line expecting a queen — which is correct.
 */
export function stripQueenPromotion(move: Uci): Uci | null {
  return movePromotion(move) === 'q' ? (move.slice(0, 4) as Uci) : null;
}
