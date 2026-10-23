import type { Uci } from './move';
import { samePlacement } from './puzzle';
import type { PieceType, Placement, Puzzle } from './puzzle';
import { buildTrie, findEdge, isTerminal } from './trie';
import type { TrieNode } from './trie';

/** Wrong tries on a single ply before the answer is shown. */
export const ATTEMPTS_BEFORE_HINT = 3;

/**
 * Pause before the opponent replies, so a move is seen rather than teleporting.
 * Measured in the repertoire trainer, not guessed.
 */
export const REPLY_MS = 450;

export type MoveOutcome =
  /**
   * Accepted. `reply` is the opponent's answer, null when nothing answers this
   * move; `finished` says the puzzle is over.
   *
   * The two are independent, and the caller must honour both. A line ending on
   * the opponent's move — you play the key move, the forced answer is played for
   * you, and that is the puzzle — arrives here as a reply *and* `finished`, so
   * treating a reply as proof there is more to come strands the puzzle.
   */
  | { kind: 'correct'; reply: Uci | null; finished: boolean }
  /**
   * Legal on the board but not an accepted continuation. The caller reverts the
   * position; the run is now failed regardless of what follows.
   */
  | { kind: 'wrong' };

export type PuzzleResult = 'solved' | 'failed';

/**
 * A wrong move, remembered with the ply it was played at.
 *
 * `ply` counts the solver's own moves, 0-based: it is how many moves had been
 * accepted when this one was rejected. That — not the raw ply of the line — is
 * the number worth showing, because it is the one the post-mortem says out
 * loud ("missed on move 2"), and it stays right whether or not the line has
 * opponent replies in it.
 *
 * The move is kept as UCI because this file has no board to turn it into SAN;
 * the caller, which does, renders it.
 */
export interface Miss {
  ply: number;
  move: Uci;
}

/**
 * Drives a single puzzle: validates moves, counts mistakes, decides when to
 * reveal the answer.
 *
 * Deliberately knows nothing about chess legality. The UI generates legal moves
 * with chess.js and calls `submit` only for moves that are legal on the board.
 * That is what makes "a mis-drag onto an illegal square is free, a legal move to
 * the wrong square is a mistake" fall out of the structure rather than out of a
 * special case — and it keeps this file testable without a board.
 */
export class PuzzleRunner {
  readonly puzzle: Puzzle;
  private node: TrieNode;

  /** Solver moves accepted so far, for the move list. */
  accepted: Uci[] = [];
  /**
   * Every wrong move, in the order played, tagged with the move it was played
   * for. Kept rather than only counted because "two wrong moves" does not tell
   * you what you played, and on a multi-move puzzle it does not even tell you
   * where the line broke — which is the thing you came to the card to learn.
   */
  misses: Miss[] = [];
  /**
   * Incorrect moves on the ply currently being asked. Resets on every accepted
   * move, so the hint budget is per ply, not per puzzle: a long line gives
   * three tries at each move rather than three for the whole thing.
   */
  wrongAtThisPly = 0;
  complete = false;
  /** True once the answer was revealed at any point this run. */
  hinted = false;

  constructor(puzzle: Puzzle) {
    this.puzzle = puzzle;
    this.node = buildTrie(puzzle.solutions);
  }

  /** Total incorrect moves this run. One slip is not clean. */
  get mistakes(): number {
    return this.misses.length;
  }

  get clean(): boolean {
    return this.mistakes === 0;
  }

  get result(): PuzzleResult {
    return this.clean ? 'solved' : 'failed';
  }

  get shouldRevealHint(): boolean {
    return this.wrongAtThisPly >= ATTEMPTS_BEFORE_HINT;
  }

  /**
   * The move to highlight once the budget is spent. A method rather than a
   * getter because reading it records that the answer was shown.
   */
  revealHint(): Uci | null {
    if (!this.shouldRevealHint || !this.node.preferredMove) return null;
    this.hinted = true;
    return this.node.preferredMove;
  }

  /** Submits a move the UI has already verified is legal. */
  submit(move: Uci): MoveOutcome {
    if (this.complete) return { kind: 'wrong' };

    const edge = findEdge(this.node, move);
    if (!edge) {
      this.wrongAtThisPly++;
      this.misses.push({ ply: this.accepted.length, move });
      return { kind: 'wrong' };
    }

    this.node = edge.next;
    this.accepted.push(move);
    this.wrongAtThisPly = 0;
    this.complete = isTerminal(edge.next);
    return { kind: 'correct', reply: edge.reply, finished: this.complete };
  }
}

/**
 * Drives a missing-piece puzzle: one square, one piece, one answer.
 *
 * A separate class rather than a mode on `PuzzleRunner`, because almost nothing
 * survives the change: there is no line to walk, no opponent reply, no trie, and
 * the answer is not a move. What is shared is the part that is actually a
 * decision — three wrong tries buys the answer, and any mistake at all costs
 * the clean solve — so those rules are the same constants, deliberately.
 *
 * Like the move runner it validates nothing about chess. The UI offers only
 * empty squares, so an unplaceable answer never reaches here.
 */
export class MissingPieceRunner {
  readonly puzzle: Puzzle;
  readonly answer: Placement;

  /**
   * The wrong placements, in order. The counterpart of the move runner's
   * `misses`, without the ply: there is only ever one question here, so what
   * you played is the whole story.
   */
  wrongGuesses: Placement[] = [];
  complete = false;
  hinted = false;

  constructor(puzzle: Puzzle, answer: Placement) {
    this.puzzle = puzzle;
    this.answer = answer;
  }

  /** Wrong guesses this run. There is one ply, so this is also the ply's count. */
  get mistakes(): number {
    return this.wrongGuesses.length;
  }

  get clean(): boolean {
    return this.mistakes === 0;
  }

  get result(): PuzzleResult {
    return this.clean ? 'solved' : 'failed';
  }

  get shouldRevealHint(): boolean {
    return this.mistakes >= ATTEMPTS_BEFORE_HINT;
  }

  /** As on the move runner, reading the answer is what records that it was shown. */
  revealHint(): Placement | null {
    if (!this.shouldRevealHint) return null;
    this.hinted = true;
    return this.answer;
  }

  /**
   * Submits a square and a piece.
   *
   * Choosing the square is not itself an answer — cancelling the piece picker
   * costs nothing, exactly as a cancelled promotion does. Only a complete guess
   * can be wrong.
   */
  submit(square: string, type: PieceType): { kind: 'correct' | 'wrong' } {
    if (this.complete) return { kind: 'wrong' };

    const guess: Placement = { color: this.answer.color, type, square };
    if (!samePlacement(guess, this.answer)) {
      this.wrongGuesses.push(guess);
      return { kind: 'wrong' };
    }

    this.complete = true;
    return { kind: 'correct' };
  }
}
