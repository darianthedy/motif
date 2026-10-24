import type { GameCollection, Library } from '../../data/backend';
import { gamesIn } from '../../model/games/library';
import { OfflineNote } from '../OfflineNote';

interface Props {
  library: Library;
  collections: GameCollection[];
  online: boolean;
  onOpen: (collection: GameCollection) => void;
  onCreate: (name: string) => void;
}

/** The Games section's front page: the collections of games. */
export function GamesHome({ library, collections, online, onOpen, onCreate }: Props) {
  const total = library.games.length;

  return (
    <div className="screen">
      <h1>Games</h1>

      {collections.length === 0 ? (
        <p className="muted">
          Nothing here yet. Make a collection, then add games to it as PGN or play them in on the
          board.
        </p>
      ) : (
        <p className="muted small">
          {total} game{total === 1 ? '' : 's'} in {collections.length} collection
          {collections.length === 1 ? '' : 's'}
        </p>
      )}

      <ul className="collections">
        {collections.map((collection) => {
          const count = gamesIn(library, collection.id).length;
          return (
            <li key={collection.id}>
              <button type="button" className="card" onClick={() => onOpen(collection)}>
                <span className="card-title">{collection.name}</span>
                <span className="muted small">
                  {count} game{count === 1 ? '' : 's'}
                </span>
              </button>
            </li>
          );
        })}
      </ul>

      <div className="menu">
        <button
          type="button"
          disabled={!online}
          onClick={() => {
            const name = prompt('Name the collection')?.trim();
            if (name) onCreate(name);
          }}
        >
          New collection
        </button>
        <OfflineNote online={online} />
      </div>
    </div>
  );
}
