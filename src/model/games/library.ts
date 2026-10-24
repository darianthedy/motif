import type { Library } from '../../data/backend';
import type { Game, GameCollection, GamePlacement, NewGame } from './game';

/** Game collections in the order they were made. */
export function gameCollectionsOf(library: Library): GameCollection[] {
  return [...library.gameCollections].sort(
    (a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : 1),
  );
}

/** A collection's games, in its own order. */
export function gamesIn(library: Library, collectionId: string): Game[] {
  return library.games
    .filter((game) => game.collectionId === collectionId)
    .sort((a, b) => a.position - b.position || (a.id < b.id ? -1 : 1));
}

function nextPosition(library: Library, collectionId: string): number {
  return gamesIn(library, collectionId).reduce((max, g) => Math.max(max, g.position + 1), 0);
}

/** New games for the end of a collection, in the order given. */
export function appendGames(
  library: Library,
  collectionId: string,
  games: Pick<NewGame, 'pgn' | 'orientation'>[],
): NewGame[] {
  const start = nextPosition(library, collectionId);
  return games.map((game, n) => ({
    id: crypto.randomUUID(),
    collectionId,
    position: start + n,
    pgn: game.pgn,
    orientation: game.orientation,
  }));
}

/** Copies of `games` at the end of another collection, or the same one. */
export function copyGames(library: Library, games: Game[], collectionId: string): NewGame[] {
  return appendGames(library, collectionId, games);
}

/** `games` moved to the end of another collection, keeping their order. */
export function moveGames(library: Library, games: Game[], collectionId: string): GamePlacement[] {
  const moving = games.filter((game) => game.collectionId !== collectionId);
  const start = nextPosition(library, collectionId);
  return moving.map((game, n) => ({ id: game.id, collectionId, position: start + n }));
}

/**
 * The game one place up (`-1`) or down (`+1`) in its collection: it swaps
 * positions with its neighbour. Empty at either end.
 */
export function shiftGame(library: Library, game: Game, by: -1 | 1): GamePlacement[] {
  const games = gamesIn(library, game.collectionId);
  const index = games.findIndex((g) => g.id === game.id);
  const other = games[index + by];
  if (index < 0 || !other) return [];
  // Equal positions would swap to the same thing, so the pair is renumbered
  // from wherever the earlier of the two stands.
  const low = Math.min(game.position, other.position);
  const [first, second] = by < 0 ? [game, other] : [other, game];
  return [
    { id: first.id, collectionId: game.collectionId, position: low },
    { id: second.id, collectionId: game.collectionId, position: low + 1 },
  ];
}
