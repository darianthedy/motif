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
  /** Accepted. `reply` is the opponent's answer, null when the line ends. */
  | { kind: 'correct'; reply: Uci | null; finished: boolean }
  /**
   * Legal on the board but not an accepted continuation. The caller reverts the
   * position; the run is now failed regardless of what follows.
   */
  | { kind: 'wrong' };

export type PuzzleResult = 'solved' | 'failed';

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
  private readonly root: TrieNode;
  private node: TrieNode;

  /** Solver moves accepted so far, for the move list. */
  accepted: Uci[] = [];
  /** Total incorrect moves this run. Never resets — one slip is not clean. */
  mistakes = 0;
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
    this.root = buildTrie(puzzle.solutions);
    this.node = this.root;
  }

  /** A puzzle with no solutions is unsolvable; flagged so it can be skipped. */
  get degenerate(): boolean {
    return isTerminal(this.root);
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
   * Peeks at the expected move without marking the run as hinted. For the
   * post-mortem on the result card.
   */
  get expectedMove(): Uci | null {
    return this.node.preferredMove;
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
      this.mistakes++;
      this.wrongAtThisPly++;
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

  /** Wrong guesses this run. There is one ply, so this is also the ply's count. */
  mistakes = 0;
  complete = false;
  hinted = false;

  constructor(puzzle: Puzzle, answer: Placement) {
    this.puzzle = puzzle;
    this.answer = answer;
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
      this.mistakes++;
      return { kind: 'wrong' };
    }

    this.complete = true;
    return { kind: 'correct' };
  }
}
