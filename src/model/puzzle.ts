import type { Uci } from './move';

export type Side = 'w' | 'b';

export type PieceType = 'p' | 'n' | 'b' | 'r' | 'q' | 'k';

/** Whether a puzzle has ever been completed, and how. */
export type PuzzleStatus = 'unseen' | 'solved' | 'failed';

/**
 * A piece and the square it belongs on: the answer to a missing-piece puzzle.
 *
 * Not a move — nothing travels from anywhere — so it is deliberately not a
 * `Uci`. Squeezing it into one would mean inventing a source square that does
 * not exist, and every trie lookup downstream would then have to know that some
 * "moves" are not moves.
 */
export interface Placement {
  color: Side;
  type: PieceType;
  square: string;
}

/**
 * Written FEN-style, so case carries the colour: `Ng6` is a white knight, `ng6`
 * a black one. An explicit `w`/`b` prefix is also accepted — `bNg6` — because
 * anyone in the habit of writing SAN will type an uppercase letter for a black
 * piece, and there has to be a way to say what you meant.
 */
const PLACEMENT_RE = /^(?:([wb])[\s-]*)?([pnbrqkPNBRQK])[\s-]*([a-h][1-8])$/;

export function parsePlacement(text: string): Placement | null {
  const match = PLACEMENT_RE.exec(text.trim());
  if (!match) return null;
  const [, prefix, piece, square] = match;
  return {
    color: prefix ? (prefix as Side) : piece === piece.toUpperCase() ? 'w' : 'b',
    type: piece.toLowerCase() as PieceType,
    square,
  };
}

/** The canonical written form, `Ng6`. Round-trips through `parsePlacement`. */
export function placementText(placement: Placement): string {
  const letter =
    placement.color === 'w' ? placement.type.toUpperCase() : placement.type;
  return `${letter}${placement.square}`;
}

export function samePlacement(a: Placement, b: Placement): boolean {
  return a.color === b.color && a.type === b.type && a.square === b.square;
}

export interface Puzzle {
  id: string;
  /** Each puzzle belongs to exactly one collection. */
  collectionId: string;
  /** Order within the collection. */
  position: number;
  fen: string;
  /**
   * Each solution is an ordered line alternating solver move, opponent reply,
   * solver move, ... Lines may share prefixes; the trie merges them.
   *
   * Empty for a missing-piece puzzle, which is answered by `addPiece` instead.
   */
  solutions: Uci[][];
  /**
   * The piece missing from the position, for the missing-piece kind: you are
   * not asked to move anything, you are asked what belongs where.
   *
   * The kind is derived from this field rather than declared in a separate
   * `kind`, so the two can never disagree — a puzzle with a placement is a
   * missing-piece puzzle, and one without is not.
   */
  addPiece?: Placement;
  /** The idea behind the puzzle. Never rendered while solving — it's a spoiler. */
  tags: string[];
  /** Free-form note. Also never rendered while solving. */
  comment?: string;
  /** The puzzle number from the file, shown as `#187`. Not a dedupe key. */
  sourceId?: string;
  rating?: number;
  addedAt: number;
}

/** What a puzzle is, apart from where it is kept: the part a file supplies. */
export type PuzzleContent = Omit<Puzzle, 'id' | 'collectionId' | 'position' | 'addedAt'>;

export interface Collection {
  id: string;
  name: string;
  createdAt: number;
}

/** A puzzle answered by placing a piece rather than by playing moves. */
export function isMissingPiece(
  puzzle: Pick<Puzzle, 'addPiece'>,
): puzzle is Pick<Puzzle, 'addPiece'> & { addPiece: Placement } {
  return Boolean(puzzle.addPiece);
}

/**
 * FEN reduced to the fields that define the position: placement, side to move,
 * castling rights, en passant square. Halfmove and fullmove counters are
 * dropped — two exports of the same puzzle that disagree only on move number
 * are the same puzzle.
 */
export function normalizeFen(fen: string): string {
  return fen.trim().split(/\s+/).slice(0, 4).join(' ');
}

/**
 * Identity for import dedupe: the position plus what counts as solving it.
 *
 * A canonical string rather than a digest. It is longer, but it cannot collide,
 * it is legible in a store dump, and at these volumes the cost is irrelevant.
 * Tags, comment, rating and source are excluded on purpose, so re-importing a
 * file with edited metadata updates the existing puzzle instead of forking it.
 */
export function contentKey(puzzle: Pick<Puzzle, 'fen' | 'solutions' | 'addPiece'>): string {
  // Solution order must not affect identity: the same two lines listed in the
  // other order are the same puzzle.
  const lines = puzzle.solutions
    .map((line) => line.join(' '))
    .sort()
    .join('|');
  // Two missing-piece puzzles can share a FEN and an empty solution list, so
  // the placement is part of the key too.
  const placement = puzzle.addPiece ? placementText(puzzle.addPiece) : '-';
  return `${normalizeFen(puzzle.fen)}/${lines}/${placement}`;
}

/**
 * Side the solver plays.
 *
 * A missing-piece puzzle is answered for the colour of the piece being added,
 * which is not always the side to move: in the archetypal example the position
 * is Black to move and the answer is a white knight that mates.
 */
export function solverSide(puzzle: Pick<Puzzle, 'fen' | 'addPiece'>): Side {
  if (puzzle.addPiece) return puzzle.addPiece.color;
  return normalizeFen(puzzle.fen).split(' ')[1] === 'b' ? 'b' : 'w';
}
