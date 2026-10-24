import { useRef, useState } from 'react';
import { DEFAULT_POSITION, validateFen } from 'chess.js';
import { parsePgnFile } from '../../model/games/pgn';
import type { ParsedGame, PgnError } from '../../model/games/pgn';
import { gameTitle } from '../../model/games/summary';
import { OfflineNote } from '../OfflineNote';

interface Props {
  collectionName: string;
  online: boolean;
  onAdd: (games: ParsedGame[]) => void;
  /** A game with no moves yet, from `fen`, to play in on the board. */
  onNewGame: (fen: string) => void;
  onExit: () => void;
}

export function AddGamesScreen({ collectionName, online, onAdd, onNewGame, onExit }: Props) {
  const [text, setText] = useState('');
  const [read, setRead] = useState<{ games: ParsedGame[]; errors: PgnError[] } | null>(null);
  const [fen, setFen] = useState('');
  const fileInput = useRef<HTMLInputElement>(null);

  const parse = (raw: string) => {
    setText(raw);
    setRead(raw.trim() ? parsePgnFile(raw) : null);
  };

  const onFiles = async (files: FileList | null) => {
    if (!files?.length) return;
    // Several files read as one: a blank line between games is all PGN asks.
    const texts = await Promise.all([...files].map((file) => file.text()));
    parse(texts.join('\n\n'));
  };

  const start = fen.trim() || DEFAULT_POSITION;
  const fenCheck = validateFen(start);
  const count = read?.games.length ?? 0;

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" onClick={onExit}>
          ← {collectionName}
        </button>
        <h2>Add games</h2>
      </header>

      <p className="muted small">
        Choose PGN files, or paste PGN. A file of many games adds them all; a FEN on its own adds
        the position, to play moves into.
      </p>

      <input
        ref={fileInput}
        type="file"
        accept=".pgn,application/x-chess-pgn,text/plain"
        multiple
        style={{ display: 'none' }}
        onChange={(event) => void onFiles(event.target.files)}
      />
      <button type="button" onClick={() => fileInput.current?.click()}>
        Choose files
      </button>

      <textarea
        value={text}
        onChange={(event) => parse(event.target.value)}
        placeholder={'[White "…"]\n[Black "…"]\n\n1. e4 e5 2. Nf3 …'}
        rows={8}
        spellCheck={false}
      />

      {read && (
        <div className="import-preview">
          <p>
            {count} game{count === 1 ? '' : 's'} read
            {read.errors.length > 0 && (
              <span className="bad"> · {read.errors.length} couldn't be read</span>
            )}
          </p>

          {read.errors.length > 0 && (
            <ul className="rejects">
              {read.errors.slice(0, 5).map((error) => (
                <li key={`${error.game}-${error.message}`} className="muted small">
                  game {error.game}: {error.message}
                </li>
              ))}
              {read.errors.length > 5 && (
                <li className="muted small">…and {read.errors.length - 5} more</li>
              )}
            </ul>
          )}

          {count > 0 && count <= 5 && (
            <ul className="groups">
              {read.games.map((game, index) => (
                <li key={index} className="small">
                  {gameTitle(game.headers)}
                </li>
              ))}
            </ul>
          )}

          <button type="button" onClick={() => onAdd(read.games)} disabled={count === 0 || !online}>
            Add {count} game{count === 1 ? '' : 's'}
          </button>
        </div>
      )}

      <h3 className="section-title">Or play one in</h3>
      <label className="field">
        <span className="muted small">Starting position (FEN), if not the usual one</span>
        <input
          value={fen}
          onChange={(event) => setFen(event.target.value)}
          placeholder="The usual starting position"
          spellCheck={false}
        />
      </label>
      {!fenCheck.ok && <p className="bad small">{fenCheck.error}</p>}
      <button type="button" onClick={() => onNewGame(start)} disabled={!fenCheck.ok || !online}>
        New game on the board
      </button>
      <OfflineNote online={online} />
    </div>
  );
}
