import { useEffect } from 'react';
import type { Backend, Game, Library } from '../../data/backend';
import { appendGames, copyGames, gameCollectionsOf, gamesIn, moveGames, shiftGame } from '../../model/games/library';
import { newGame, writePgn } from '../../model/games/pgn';
import type { ParsedGame } from '../../model/games/pgn';
import { AddGamesScreen } from './AddGamesScreen';
import { GameCollectionScreen } from './GameCollectionScreen';
import { GameScreen } from './GameScreen';
import { GamesHome } from './GamesHome';
import './games.css';

export type GamesRoute =
  | { name: 'home' }
  | { name: 'collection'; id: string }
  | { name: 'add'; collectionId: string }
  | { name: 'game'; collectionId: string; gameId: string };

/** Somewhere else instead, for a screen whose game or collection has gone. */
function Redirect({ to, onNavigate }: { to: GamesRoute; onNavigate: (route: GamesRoute) => void }) {
  useEffect(() => onNavigate(to));
  return null;
}

const games = (n: number) => `${n} game${n === 1 ? '' : 's'}`;

interface Props {
  library: Library;
  online: boolean;
  route: GamesRoute;
  onNavigate: (route: GamesRoute) => void;
  /** Runs an online edit, reporting a failure rather than dropping it. */
  edit: (fn: (backend: Backend) => Promise<void>, done?: string) => Promise<boolean>;
  onClearNotice: () => void;
}

/** Collections of games, and the games themselves. */
export function GamesSection({
  library,
  online,
  route,
  onNavigate: setRoute,
  edit,
  onClearNotice,
}: Props) {
  // Going somewhere yourself leaves the last notice behind; arriving after an
  // edit (setRoute) keeps the one that edit just set.
  const go = (to: GamesRoute) => {
    onClearNotice();
    setRoute(to);
  };
  const collectionOf = (id: string) => library.gameCollections.find((c) => c.id === id);
  const nameOf = (id: string) => collectionOf(id)?.name ?? 'the collection';

  if (route.name === 'game') {
    const game = library.games.find((g) => g.id === route.gameId);
    const collection = collectionOf(route.collectionId);
    if (!game || !collection) {
      return <Redirect to={{ name: 'collection', id: route.collectionId }} onNavigate={setRoute} />;
    }
    return (
      <GameScreen
        // A different game starts again at its first position.
        key={game.id}
        game={game}
        collectionName={collection.name}
        online={online}
        onSave={(pgn) => edit((backend) => backend.updateGame(game.id, { pgn }))}
        onOrientation={(orientation) => edit((backend) => backend.updateGame(game.id, { orientation }))}
        onDelete={() =>
          void edit((backend) => backend.deleteGames([game.id])).then((deleted) => {
            if (deleted) setRoute({ name: 'collection', id: collection.id });
          })
        }
        onExit={() => go({ name: 'collection', id: collection.id })}
      />
    );
  }

  if (route.name === 'add') {
    const collection = collectionOf(route.collectionId);
    if (!collection) return <Redirect to={{ name: 'home' }} onNavigate={setRoute} />;

    const add = async (parsed: ParsedGame[]) => {
      // Stored as written here, so every stored game reads back the same way.
      const added = appendGames(
        library,
        collection.id,
        parsed.map((game) => ({ pgn: writePgn(game), orientation: 'w' })),
      );
      const saved = await edit((backend) => backend.addGames(added), `Added ${games(added.length)}.`);
      if (saved) setRoute({ name: 'collection', id: collection.id });
    };

    const start = async (fen: string) => {
      const [game] = appendGames(library, collection.id, [
        { pgn: writePgn(newGame(fen)), orientation: fen.split(' ')[1] === 'b' ? 'b' : 'w' },
      ]);
      const saved = await edit((backend) => backend.addGames([game]));
      if (saved) setRoute({ name: 'game', collectionId: collection.id, gameId: game.id });
    };

    return (
      <AddGamesScreen
        collectionName={collection.name}
        online={online}
        onAdd={(parsed) => void add(parsed)}
        onNewGame={(fen) => void start(fen)}
        onExit={() => go({ name: 'collection', id: collection.id })}
      />
    );
  }

  if (route.name === 'collection') {
    const collection = collectionOf(route.id);
    if (!collection) return <Redirect to={{ name: 'home' }} onNavigate={setRoute} />;

    return (
      <GameCollectionScreen
        collection={collection}
        collections={gameCollectionsOf(library)}
        games={gamesIn(library, collection.id)}
        online={online}
        onOpen={(game: Game) => go({ name: 'game', collectionId: collection.id, gameId: game.id })}
        onAdd={() => go({ name: 'add', collectionId: collection.id })}
        onMove={(chosen, into) => {
          const placements = moveGames(library, chosen, into);
          return edit(
            (backend) => backend.placeGames(placements),
            `Moved ${games(placements.length)} to ${nameOf(into)}.`,
          );
        }}
        onCopy={(chosen, into) => {
          const copies = copyGames(library, chosen, into);
          return edit(
            (backend) => backend.addGames(copies),
            `Copied ${games(copies.length)} to ${nameOf(into)}.`,
          );
        }}
        onDeleteGames={(chosen) =>
          edit(
            (backend) => backend.deleteGames(chosen.map((g) => g.id)),
            `Deleted ${games(chosen.length)}.`,
          )
        }
        onShift={(game, by) => {
          const placements = shiftGame(library, game, by);
          if (placements.length) void edit((backend) => backend.placeGames(placements));
        }}
        onRename={(name) => void edit((backend) => backend.renameGameCollection(collection.id, name))}
        onDelete={() =>
          void edit((backend) => backend.deleteGameCollection(collection.id)).then((deleted) => {
            if (deleted) setRoute({ name: 'home' });
          })
        }
        onExit={() => go({ name: 'home' })}
      />
    );
  }

  return (
    <GamesHome
      library={library}
      collections={gameCollectionsOf(library)}
      online={online}
      onOpen={(collection) => go({ name: 'collection', id: collection.id })}
      onCreate={(name) => {
        const id = crypto.randomUUID();
        void edit((backend) => backend.createGameCollections([{ id, name, createdAt: Date.now() }])).then(
          (created) => {
            if (created) setRoute({ name: 'collection', id });
          },
        );
      }}
    />
  );
}
