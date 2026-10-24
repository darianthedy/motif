import { useMemo, useState } from 'react';
import type { Game, GameCollection } from '../../data/backend';
import { readHeaders } from '../../model/games/pgn';
import { gameSubtitle, gameTitle, matchesSearch } from '../../model/games/summary';
import { OfflineNote } from '../OfflineNote';
import { downloadText, fileName } from './download';

type Mode = 'browse' | 'select' | 'reorder';

interface Props {
  collection: GameCollection;
  /** Every game collection, to move or copy into. */
  collections: GameCollection[];
  /** In the collection's order. */
  games: Game[];
  online: boolean;
  onOpen: (game: Game) => void;
  onAdd: () => void;
  onMove: (games: Game[], collectionId: string) => Promise<boolean>;
  onCopy: (games: Game[], collectionId: string) => Promise<boolean>;
  onDeleteGames: (games: Game[]) => Promise<boolean>;
  onShift: (game: Game, by: -1 | 1) => void;
  onRename: (name: string) => void;
  onDelete: () => void;
  onExit: () => void;
}

/** All of `games` as one PGN file. */
const asFile = (games: Game[]) => games.map((game) => game.pgn.trimEnd()).join('\n\n') + '\n';

export function GameCollectionScreen({
  collection,
  collections,
  games,
  online,
  onOpen,
  onAdd,
  onMove,
  onCopy,
  onDeleteGames,
  onShift,
  onRename,
  onDelete,
  onExit,
}: Props) {
  const [mode, setMode] = useState<Mode>('browse');
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [target, setTarget] = useState('');

  const headers = useMemo(() => new Map(games.map((g) => [g.id, readHeaders(g.pgn)])), [games]);
  const shown =
    mode === 'reorder' ? games : games.filter((g) => matchesSearch(headers.get(g.id) ?? {}, query));
  const chosen = games.filter((g) => selected.has(g.id));
  const others = collections.filter((c) => c.id !== collection.id);
  // Copying into the same collection is a fine way to keep a version.
  const into = target || others[0]?.id || collection.id;

  const setModeTo = (next: Mode) => {
    setMode(next);
    setSelected(new Set());
  };

  const toggle = (id: string) =>
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const afterBulk = (ok: boolean) => {
    if (ok) setModeTo('browse');
  };

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" onClick={onExit}>
          ← Games
        </button>
        <h2>{collection.name}</h2>
      </header>

      <p className="muted small">
        {games.length} game{games.length === 1 ? '' : 's'}
      </p>

      {mode === 'browse' && (
        <div className="menu">
          <button type="button" onClick={onAdd} disabled={!online}>
            Add games
          </button>
        </div>
      )}

      {games.length > 0 && (
        <div className="filters">
          {(['browse', 'select', 'reorder'] as Mode[]).map((option) => (
            <button
              key={option}
              type="button"
              className="chip"
              data-active={mode === option || undefined}
              disabled={option !== 'browse' && !online}
              onClick={() => setModeTo(option)}
            >
              {option === 'browse' ? 'Browse' : option === 'select' ? 'Select' : 'Reorder'}
            </button>
          ))}
        </div>
      )}

      {games.length > 1 && mode !== 'reorder' && (
        <input
          className="search"
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search players, event, opening…"
        />
      )}

      {mode === 'select' && (
        <div className="bulk">
          <div className="row">
            <span className="muted small">{chosen.length} selected</span>
            <button
              type="button"
              className="link"
              onClick={() =>
                setSelected(
                  chosen.length === shown.length ? new Set() : new Set(shown.map((g) => g.id)),
                )
              }
            >
              {chosen.length === shown.length ? 'Select none' : 'Select all'}
            </button>
          </div>
          <label className="field">
            <span className="muted small">Move or copy to</span>
            <select value={into} onChange={(event) => setTarget(event.target.value)}>
              {others.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
              <option value={collection.id}>{collection.name} (this one)</option>
            </select>
          </label>
          <div className="row wrap">
            <button
              type="button"
              disabled={!chosen.length || !online || into === collection.id}
              onClick={() => void onMove(chosen, into).then(afterBulk)}
            >
              Move
            </button>
            <button
              type="button"
              disabled={!chosen.length || !online}
              onClick={() => void onCopy(chosen, into).then(afterBulk)}
            >
              Copy
            </button>
            <button
              type="button"
              disabled={!chosen.length}
              onClick={() => downloadText(fileName(collection.name, 'pgn'), asFile(chosen))}
            >
              Export
            </button>
            <button
              type="button"
              className="danger"
              disabled={!chosen.length || !online}
              onClick={() => {
                if (confirm(`Delete ${chosen.length} game${chosen.length === 1 ? '' : 's'}?`)) {
                  void onDeleteGames(chosen).then(afterBulk);
                }
              }}
            >
              Delete
            </button>
          </div>
        </div>
      )}

      {shown.length === 0 ? (
        games.length > 0 && <p className="muted small">No game matches.</p>
      ) : (
        <ol className="puzzle-list">
          {shown.map((game) => {
            const h = headers.get(game.id) ?? {};
            const index = games.indexOf(game);
            const subtitle = gameSubtitle(h);
            const label = (
              <span className="row-main">
                <span className="game-title">{gameTitle(h)}</span>
                {subtitle && <span className="muted small">{subtitle}</span>}
              </span>
            );
            return (
              <li key={game.id}>
                {mode === 'browse' && (
                  <button type="button" className="puzzle-row" onClick={() => onOpen(game)}>
                    <span className="muted index">{index + 1}</span>
                    {label}
                  </button>
                )}
                {mode === 'select' && (
                  <button
                    type="button"
                    className="puzzle-row"
                    aria-pressed={selected.has(game.id)}
                    onClick={() => toggle(game.id)}
                  >
                    <span className="check" data-checked={selected.has(game.id) || undefined} />
                    {label}
                  </button>
                )}
                {mode === 'reorder' && (
                  <div className="puzzle-row">
                    <span className="muted index">{index + 1}</span>
                    {label}
                    <button
                      type="button"
                      className="link"
                      aria-label="Move up"
                      disabled={index === 0 || !online}
                      onClick={() => onShift(game, -1)}
                    >
                      ↑
                    </button>
                    <button
                      type="button"
                      className="link"
                      aria-label="Move down"
                      disabled={index === games.length - 1 || !online}
                      onClick={() => onShift(game, 1)}
                    >
                      ↓
                    </button>
                  </div>
                )}
              </li>
            );
          })}
        </ol>
      )}

      <div className="menu subtle">
        <button
          type="button"
          className="link"
          disabled={!games.length}
          onClick={() => downloadText(fileName(collection.name, 'pgn'), asFile(games))}
        >
          Export collection as PGN
        </button>
        <button
          type="button"
          className="link"
          disabled={!online}
          onClick={() => {
            const name = prompt('Rename the collection', collection.name)?.trim();
            if (name && name !== collection.name) onRename(name);
          }}
        >
          Rename collection
        </button>
        <button
          type="button"
          className="link danger"
          disabled={!online}
          onClick={() => {
            if (confirm(`Delete "${collection.name}" and its games?`)) onDelete();
          }}
        >
          Delete collection
        </button>
        <OfflineNote online={online} />
      </div>
    </div>
  );
}
