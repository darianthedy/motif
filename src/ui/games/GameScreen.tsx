import { useEffect, useMemo, useRef, useState } from 'react';
import type { Game } from '../../data/backend';
import {
  deleteFrom,
  fenAt,
  forward,
  nodeAt,
  onMainLine,
  playMove,
  promoteVariation,
  setComment,
  setHeaders,
  validPath,
} from '../../model/games/edit';
import type { MovePath } from '../../model/games/edit';
import { parsePgn, RESULTS, writePgn } from '../../model/games/pgn';
import type { ParsedGame } from '../../model/games/pgn';
import { gameTitle } from '../../model/games/summary';
import { moveFrom, moveTo } from '../../model/move';
import type { Uci } from '../../model/move';
import type { Side } from '../../model/puzzle';
import { Board } from '../Board';
import { OfflineNote } from '../OfflineNote';
import { downloadText, fileName } from './download';
import { MoveList } from './MoveList';

/** The headers the Details tab edits, in the order it shows them. */
const DETAILS: { name: string; label: string }[] = [
  { name: 'White', label: 'White' },
  { name: 'WhiteElo', label: 'White rating' },
  { name: 'Black', label: 'Black' },
  { name: 'BlackElo', label: 'Black rating' },
  { name: 'Event', label: 'Event' },
  { name: 'Site', label: 'Site' },
  { name: 'Date', label: 'Date (YYYY.MM.DD)' },
  { name: 'Round', label: 'Round' },
  { name: 'Opening', label: 'Opening' },
  { name: 'ECO', label: 'ECO' },
];

/** PGN's `?` for unknown is shown as an empty field. */
const shownValue = (value: string | undefined) => (value && !/^[?.]*$/.test(value) ? value : '');

/**
 * What an empty field saves as. The seven headers PGN asks every game to have
 * go back to its marks for unknown; any other is removed.
 */
const UNKNOWN: Record<string, string> = {
  Event: '?',
  Site: '?',
  Date: '????.??.??',
  Round: '?',
  White: '?',
  Black: '?',
};

interface Props {
  game: Game;
  collectionName: string;
  online: boolean;
  /** Each resolves once saved, to whether it was. */
  onSave: (pgn: string) => Promise<boolean>;
  onOrientation: (side: Side) => Promise<boolean>;
  onDelete: () => void;
  onExit: () => void;
}

/**
 * One game, to step through and annotate.
 *
 * Playing a move on the board adds it: at the end of a line it carries the
 * line on, anywhere else it starts a variation. Every change saves the whole
 * PGN straight away, as a puzzle's comment does — there is no Save to forget.
 * Offline it is read-only, like every other edit.
 */
export function GameScreen({
  game,
  collectionName,
  online,
  onSave,
  onOrientation,
  onDelete,
  onExit,
}: Props) {
  const stored = useMemo(() => {
    try {
      return parsePgn(game.pgn);
    } catch {
      return null;
    }
  }, [game.pgn]);

  // An edit shows at once, ahead of the save and the reload behind it.
  const [draft, setDraft] = useState<ParsedGame | null>(null);
  const [path, setPath] = useState<MovePath>([]);
  const [tab, setTab] = useState<'moves' | 'details'>('moves');
  const [orientation, setOrientation] = useState<Side>(game.orientation);
  const [problem, setProblem] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  // Saves go one at a time, in order, so a quick second edit can never land
  // before the first and be overwritten by it.
  const saving = useRef<Promise<void>>(Promise.resolve());
  const pending = useRef(0);

  useEffect(() => setOrientation(game.orientation), [game.orientation]);

  // A newer copy from the server replaces the draft, unless more of this
  // screen's own edits are still on their way.
  useEffect(() => {
    if (pending.current === 0) setDraft(null);
  }, [game.pgn]);

  const tree = draft ?? stored;

  if (!tree) {
    return (
      <div className="screen">
        <header className="screen-bar">
          <button type="button" className="link" aria-label={`Back to ${collectionName}`} onClick={onExit}>
            ←
          </button>
          <h2>Game</h2>
        </header>
        <p className="bad">This game's PGN can't be read.</p>
        <pre className="fen">{game.pgn}</pre>
      </div>
    );
  }

  const at = validPath(tree, path) ? path : [];
  const node = nodeAt(tree, at);

  const save = (next: ParsedGame) => {
    setDraft(next);
    setProblem(null);
    pending.current++;
    const text = writePgn(next);
    saving.current = saving.current.then(async () => {
      const ok = await onSave(text);
      pending.current--;
      // The failure itself is reported by the app's notice.
      if (!ok && pending.current === 0) setDraft(null);
    });
  };

  const onMove = (move: Uci) => {
    try {
      const result = playMove(tree, at, move);
      if (result.game !== tree) save(result.game);
      setPath(result.path);
    } catch (error) {
      setProblem((error as Error).message);
    }
  };

  const flip = () => {
    const next: Side = orientation === 'w' ? 'b' : 'w';
    setOrientation(next);
    void onOrientation(next).then((ok) => {
      if (!ok) setOrientation(game.orientation);
    });
  };

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" aria-label={`Back to ${collectionName}`} onClick={onExit}>
          ←
        </button>
        <h2>{gameTitle(tree.headers)}</h2>
      </header>

      <div className="filters">
        <button
          type="button"
          className="chip"
          data-active={tab === 'moves' || undefined}
          onClick={() => setTab('moves')}
        >
          Moves
        </button>
        <button
          type="button"
          className="chip"
          data-active={tab === 'details' || undefined}
          onClick={() => setTab('details')}
        >
          Details
        </button>
      </div>

      {problem && <p className="bad small">{problem}</p>}

      {tab === 'moves' ? (
        <>
          <Board
            fen={fenAt(tree, at)}
            orientation={orientation}
            onMove={onMove}
            interactive={online}
            highlight={node ? { from: moveFrom(node.uci), to: moveTo(node.uci) } : null}
          />

          <Stepper
            tree={tree}
            path={at}
            onGo={setPath}
            onFlip={flip}
            canFlip={online}
          />

          <MoveList game={tree} path={at} onGo={setPath} />

          <CommentEditor
            key={at.join('.')}
            label={node ? `After ${node.san}` : 'Note on the game'}
            value={node ? node.comment : tree.comment}
            online={online}
            onSave={(text) => save(setComment(tree, at, text))}
          />

          <div className="row wrap">
            {!onMainLine(at) && (
              <button
                type="button"
                className="link"
                disabled={!online}
                onClick={() => {
                  const result = promoteVariation(tree, at);
                  save(result.game);
                  setPath(result.path);
                }}
              >
                Make main line
              </button>
            )}
            {node && (
              <button
                type="button"
                className="link danger"
                disabled={!online}
                onClick={() => {
                  if (!confirm(`Delete ${node.san} and every move after it?`)) return;
                  const result = deleteFrom(tree, at);
                  save(result.game);
                  setPath(result.path);
                }}
              >
                Delete from here
              </button>
            )}
          </div>
        </>
      ) : (
        <DetailsForm
          key={JSON.stringify(tree.headers)}
          headers={tree.headers}
          online={online}
          onSave={(changes) => save(setHeaders(tree, changes))}
        />
      )}

      <div className="menu subtle">
        <button
          type="button"
          className="link"
          onClick={() => {
            void navigator.clipboard?.writeText(writePgn(tree)).then(() => {
              setCopied(true);
              window.setTimeout(() => setCopied(false), 1500);
            });
          }}
        >
          {copied ? 'Copied' : 'Copy PGN'}
        </button>
        <button
          type="button"
          className="link"
          onClick={() => downloadText(fileName(gameTitle(tree.headers), 'pgn'), writePgn(tree))}
        >
          Download PGN
        </button>
        <button
          type="button"
          className="link danger"
          disabled={!online}
          onClick={() => {
            if (confirm('Delete this game?')) onDelete();
          }}
        >
          Delete game
        </button>
        <OfflineNote online={online} />
      </div>
    </div>
  );
}

function Stepper({
  tree,
  path,
  onGo,
  onFlip,
  canFlip,
}: {
  tree: ParsedGame;
  path: MovePath;
  onGo: (path: MovePath) => void;
  onFlip: () => void;
  canFlip: boolean;
}) {
  const back = path.length ? path.slice(0, -1) : null;
  const next = forward(tree, path);
  const end = () => {
    let at = path;
    for (let step = forward(tree, at); step; step = forward(tree, at)) at = step;
    return at;
  };

  // Arrow keys step through, unless they are moving a cursor somewhere.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target?.closest('input, textarea, select')) return;
      if (event.key === 'ArrowLeft' && back) onGo(back);
      else if (event.key === 'ArrowRight' && next) onGo(next);
      else return;
      event.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <div className="replay">
      {/* Latin-1 guillemets, as on the puzzle screen: the media-control
          codepoints have emoji presentations. */}
      <button type="button" className="link" disabled={!back} onClick={() => onGo([])}>
        «
      </button>
      <button type="button" className="link" disabled={!back} onClick={() => back && onGo(back)}>
        ←
      </button>
      <button type="button" className="link" disabled={!next} onClick={() => next && onGo(next)}>
        →
      </button>
      <button type="button" className="link" disabled={!next} onClick={() => onGo(end())}>
        »
      </button>
      <span className="spacer" />
      <button type="button" className="link" disabled={!canFlip} onClick={onFlip}>
        Flip board
      </button>
    </div>
  );
}

function CommentEditor({
  label,
  value,
  online,
  onSave,
}: {
  label: string;
  value: string | undefined;
  online: boolean;
  onSave: (text: string) => void;
}) {
  const [text, setText] = useState(value ?? '');
  const changed = text.trim() !== (value ?? '');
  return (
    <div className="comment-editor">
      <label className="field">
        <span className="muted small">{label}</span>
        <textarea
          value={text}
          onChange={(event) => setText(event.target.value)}
          rows={2}
          placeholder="A comment"
          disabled={!online}
        />
      </label>
      {changed && (
        <button type="button" onClick={() => onSave(text)} disabled={!online}>
          Save comment
        </button>
      )}
    </div>
  );
}

function DetailsForm({
  headers,
  online,
  onSave,
}: {
  headers: Record<string, string>;
  online: boolean;
  onSave: (changes: Record<string, string>) => void;
}) {
  const initial = () => {
    const values: Record<string, string> = { Result: headers.Result ?? '*' };
    for (const { name } of DETAILS) values[name] = shownValue(headers[name]);
    return values;
  };
  const [values, setValues] = useState(initial);
  const before = initial();
  const changed = Object.keys(values).some((name) => values[name].trim() !== before[name]);

  const set = (name: string, value: string) => setValues((current) => ({ ...current, [name]: value }));

  return (
    <div className="details-form">
      {DETAILS.map(({ name, label }) => (
        <label key={name} className="field">
          <span className="muted small">{label}</span>
          <input
            value={values[name]}
            onChange={(event) => set(name, event.target.value)}
            disabled={!online}
          />
        </label>
      ))}
      <label className="field">
        <span className="muted small">Result</span>
        <select
          value={values.Result}
          onChange={(event) => set('Result', event.target.value)}
          disabled={!online}
        >
          {RESULTS.map((result) => (
            <option key={result} value={result}>
              {result === '*' ? 'Unfinished or unknown' : result}
            </option>
          ))}
        </select>
      </label>
      <button
        type="button"
        disabled={!changed || !online}
        onClick={() =>
          onSave(
            Object.fromEntries(
              Object.entries(values).map(([name, value]) => [
                name,
                value.trim() || (name in headers ? (UNKNOWN[name] ?? '') : ''),
              ]),
            ),
          )
        }
      >
        Save details
      </button>
    </div>
  );
}
