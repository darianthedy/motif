import type { Side } from '../puzzle';

/**
 * A collection of games. Kept apart from puzzle collections on purpose: a
 * game is read, not solved, so it has no runs and no progress, and nothing in
 * Puzzles has to learn to step around one.
 */
export interface GameCollection {
  id: string;
  name: string;
  createdAt: number;
}

export interface Game {
  /** Set by the device that adds it, so it can be opened straight away. */
  id: string;
  collectionId: string;
  /** Order within the collection. */
  position: number;
  /** The whole game: headers, moves, comments and variations. */
  pgn: string;
  /** Which side is at the bottom of the board. Kept, so a flip stays flipped. */
  orientation: Side;
  addedAt: number;
}

export type NewGame = Omit<Game, 'addedAt'>;

/** Where a game is: what moving or reordering changes. */
export interface GamePlacement {
  id: string;
  collectionId: string;
  position: number;
}
