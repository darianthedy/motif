import { describe, expect, it } from 'vitest';
import { emptyLibrary } from '../../data/backend';
import type { Library } from '../../data/backend';
import type { Game } from './game';
import { appendGames, copyGames, gamesIn, moveGames, shiftGame } from './library';

const game = (id: string, collectionId: string, position: number): Game => ({
  id,
  collectionId,
  position,
  pgn: '*',
  orientation: 'w',
  addedAt: 0,
});

function library(games: Game[]): Library {
  return {
    ...emptyLibrary(),
    gameCollections: [
      { id: 'a', name: 'A', createdAt: 0 },
      { id: 'b', name: 'B', createdAt: 1 },
    ],
    games,
  };
}

describe('placing games in collections', () => {
  const lib = library([game('x', 'a', 0), game('y', 'a', 3), game('z', 'b', 0)]);

  it('lists a collection in its order', () => {
    expect(gamesIn(lib, 'a').map((g) => g.id)).toEqual(['x', 'y']);
  });

  it('appends new games after the last one, with new ids', () => {
    const added = appendGames(lib, 'a', [
      { pgn: '1. e4 *', orientation: 'w' },
      { pgn: '1. d4 *', orientation: 'b' },
    ]);
    expect(added.map((g) => [g.collectionId, g.position, g.orientation])).toEqual([
      ['a', 4, 'w'],
      ['a', 5, 'b'],
    ]);
    expect(new Set(added.map((g) => g.id)).size).toBe(2);
  });

  it('copies games, leaving the originals where they are', () => {
    const copies = copyGames(lib, gamesIn(lib, 'a'), 'b');
    expect(copies.map((g) => [g.collectionId, g.position])).toEqual([
      ['b', 1],
      ['b', 2],
    ]);
    expect(copies.some((g) => g.id === 'x' || g.id === 'y')).toBe(false);
  });

  it('moves games to the end of another collection, skipping any already there', () => {
    expect(moveGames(lib, [lib.games[0], lib.games[2]], 'b')).toEqual([
      { id: 'x', collectionId: 'b', position: 1 },
    ]);
  });

  it('swaps a game with its neighbour, and does nothing at either end', () => {
    expect(shiftGame(lib, lib.games[1], -1)).toEqual([
      { id: 'y', collectionId: 'a', position: 0 },
      { id: 'x', collectionId: 'a', position: 1 },
    ]);
    expect(shiftGame(lib, lib.games[0], 1)).toEqual([
      { id: 'y', collectionId: 'a', position: 0 },
      { id: 'x', collectionId: 'a', position: 1 },
    ]);
    expect(shiftGame(lib, lib.games[0], -1)).toEqual([]);
    expect(shiftGame(lib, lib.games[1], 1)).toEqual([]);
  });
});
