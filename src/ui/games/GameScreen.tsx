import { useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
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
import { moveNumber, parsePgn, RESULTS, writePgn } from '../../model/games/pgn';
import type { MoveNode, ParsedGame } from '../../model/games/pgn';
import { displayComment, gameSubtitle, gameTitle } from '../../model/games/summary';
import { movesFrom } from '../../model/games/table';
import { moveFrom, moveTo } from '../../model/move';
import type { Uci } from '../../model/move';
import type { Side } from '../../model/puzzle';
import { Board } from '../Board';
import { OfflineNote } from '../OfflineNote';
import { downloadText, fileName } from './download';
import { MoveList } from './MoveList';
import { Sheet } from './Sheet';

/** The headers the details sheet edits, in the order it shows them. */
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

/** Stroke icons, drawn in the text colour. */
const icon = (d: string, size = 22) => (
  <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
    <path d={d} />
  </svg>
);
const ICONS = {
  back: icon('M19 12H5M12 19l-7-7 7-7'),
  more: (
    <svg aria-hidden="true" width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
      <circle cx="5" cy="12" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="19" cy="12" r="1.8" />
    </svg>
  ),
  flip: icon('M7 4v16M7 20l-3-3M7 20l3-3M17 20V4M17 4l-3 3M17 4l3 3'),
  start: icon('M6 5v14M18 6l-7 6 7 6'),
  previous: icon('M15 5l-7 7 7 7', 28),
  next: icon('M9 5l7 7-7 7', 28),
  end: icon('M18 5v14M6 6l7 6-7 6'),
  comment: icon('M4 5h16v11H9l-5 4V5z'),
  edit: icon('M4 20h4L19 9l-4-4L4 16v4zM14 6l4 4', 20),
  copy: icon('M8 8h12v12H8zM16 8V4H4v12h4', 20),
  download: icon('M12 4v11M7 10l5 5 5-5M5 20h14', 20),
  promote: icon('M12 20V4M6 10l6-6 6 6', 20),
  trash: icon('M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3', 20),
};

/** `3... e5`, as the move reads on its own. */
function moveName(game: ParsedGame, path: MovePath, node: MoveNode): string {
  return `${moveNumber(fenAt(game, path.slice(0, -1)), true)} ${node.san}`;
}

/** The move `path`'s is an alternative to. */
const mainAlternative = (path: MovePath): MovePath => [...path.slice(0, -1), 0];

type Panel ='comment' | 'move' | 'menu' | 'details' | null;

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
 * The screen does not scroll: the board, the next moves, the comment and the
 * controls stay where they are and only the move list scrolls, so the board
 * is always in sight. Everything that changes the game opens in a sheet.
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
  const [panel, setPanel] = useState<Panel>(null);
  const [orientation, setOrientation] = useState<Side>(game.orientation);
  const [problem, setProblem] = useState<string | null>(null);

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
  const back = (
    <button type="button" className="icon-button" aria-label={`Back to ${collectionName}`} onClick={onExit}>
      {ICONS.back}
    </button>
  );

  if (!tree) {
    return (
      <div className="game">
        <header className="game-bar">
          {back}
          <div className="game-heading">
            <h2>Game</h2>
          </div>
        </header>
        <div className="game-unreadable">
          <p className="bad">This game's PGN can't be read.</p>
          <pre className="fen">{game.pgn}</pre>
        </div>
      </div>
    );
  }

  const at = validPath(tree, path) ? path : [];
  const node = nodeAt(tree, at);
  const following = node ? node.children : tree.moves;
  const comment = node
    ? [displayComment(node.before), displayComment(node.comment)].filter(Boolean).join(' ')
    : displayComment(tree.comment);

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

  const promote = () => {
    const result = promoteVariation(tree, at);
    save(result.game);
    setPath(result.path);
    setPanel(null);
  };

  const deleteHere = () => {
    if (!node || !confirm(`Delete ${node.san} and every move after it?`)) return;
    const result = deleteFrom(tree, at);
    save(result.game);
    setPath(result.path);
    setPanel(null);
  };

  /** What can be done with the current move, in the move sheet and the menu alike. */
  const moveActions = node && (
    <>
      {!onMainLine(at) && (
        <SheetAction icon={ICONS.promote} disabled={!online} onClick={promote}>
          Make main line
        </SheetAction>
      )}
      <SheetAction
        icon={ICONS.trash}
        danger
        disabled={!online}
        aside={`${movesFrom(node)} move${movesFrom(node) === 1 ? '' : 's'}`}
        onClick={deleteHere}
      >
        Delete from here
      </SheetAction>
    </>
  );

  return (
    <div className="game">
      <header className="game-bar">
        {back}
        <div className="game-heading">
          <h2>{gameTitle(tree.headers)}</h2>
          {gameSubtitle(tree.headers) && <span className="muted">{gameSubtitle(tree.headers)}</span>}
        </div>
        <button type="button" className="icon-button" aria-label="Game actions" onClick={() => setPanel('menu')}>
          {ICONS.more}
        </button>
      </header>

      <div className="game-board">
        <Board
          fen={fenAt(tree, at)}
          orientation={orientation}
          onMove={onMove}
          interactive={online}
          highlight={node ? { from: moveFrom(node.uci), to: moveTo(node.uci) } : null}
        />
      </div>

      {problem && <p className="bad small game-problem">{problem}</p>}

      <div className="game-next">
        <span className="next-label">Next</span>
        {following.map((next, index) => (
          <button
            key={index}
            type="button"
            className="next-move"
            data-main={index === 0 || undefined}
            onClick={() => setPath([...at, index])}
          >
            {moveNumber(fenAt(tree, at), true)} {next.san}
          </button>
        ))}
        {!following.length && <span className="muted small">End of the line</span>}
      </div>

      {online ? (
        <button
          type="button"
          className="comment-strip"
          data-empty={!comment || undefined}
          onClick={() => setPanel('comment')}
        >
          {comment || (node ? 'Add a comment' : 'Add a note on the game')}
        </button>
      ) : (
        comment && <p className="comment-strip">{comment}</p>
      )}

      <MoveList
        game={tree}
        path={at}
        onGo={setPath}
        onHold={(held) => {
          setPath(held);
          setPanel('move');
        }}
      />

      <Controls
        tree={tree}
        path={at}
        online={online}
        onGo={setPath}
        onFlip={flip}
        onComment={() => setPanel('comment')}
      />

      {panel === 'comment' && (
        <Sheet label="Comment" onClose={() => setPanel(null)}>
          <CommentEditor
            label={node ? moveName(tree, at, node) : null}
            value={node ? node.comment : tree.comment}
            onCancel={() => setPanel(null)}
            onSave={(text) => {
              save(setComment(tree, at, text));
              setPanel(null);
            }}
          />
        </Sheet>
      )}

      {panel === 'move' && node && (
        <Sheet label={`Actions for ${moveName(tree, at, node)}`} onClose={() => setPanel(null)}>
          <div className="sheet-heading">
            <span className="sheet-move">{moveName(tree, at, node)}</span>
            {!onMainLine(at) && <span className="tag">variation</span>}
            {at[at.length - 1] !== 0 && (
              <span className="muted small aside">
                instead of {moveName(tree, mainAlternative(at), nodeAt(tree, mainAlternative(at))!)}
              </span>
            )}
          </div>
          <SheetAction icon={ICONS.comment} disabled={!online} onClick={() => setPanel('comment')}>
            {node.comment ? 'Edit comment' : 'Add comment'}
          </SheetAction>
          {moveActions}
          <OfflineNote online={online} />
          <button type="button" className="sheet-cancel" onClick={() => setPanel(null)}>
            Cancel
          </button>
        </Sheet>
      )}

      {panel === 'menu' && (
        <Sheet label="Game actions" onClose={() => setPanel(null)}>
          <p className="sheet-title">{gameTitle(tree.headers)}</p>
          <SheetAction icon={ICONS.edit} aside="players, event, result" onClick={() => setPanel('details')}>
            Edit details
          </SheetAction>
          <CopyAction text={writePgn(tree)} onDone={() => setPanel(null)} />
          <SheetAction
            icon={ICONS.download}
            onClick={() => {
              downloadText(fileName(gameTitle(tree.headers), 'pgn'), writePgn(tree));
              setPanel(null);
            }}
          >
            Download PGN
          </SheetAction>
          {node && <p className="sheet-title">This move, {moveName(tree, at, node)}</p>}
          {moveActions}
          <SheetAction
            icon={ICONS.trash}
            danger
            disabled={!online}
            onClick={() => {
              if (confirm('Delete this game?')) onDelete();
            }}
          >
            Delete game
          </SheetAction>
          <OfflineNote online={online} />
          <button type="button" className="sheet-cancel" onClick={() => setPanel(null)}>
            Cancel
          </button>
        </Sheet>
      )}

      {panel === 'details' && (
        <Sheet label="Details" onClose={() => setPanel(null)}>
          <p className="sheet-title">Details</p>
          <DetailsForm
            headers={tree.headers}
            online={online}
            onSave={(changes) => {
              save(setHeaders(tree, changes));
              setPanel(null);
            }}
          />
          <OfflineNote online={online} />
          <button type="button" className="sheet-cancel" onClick={() => setPanel(null)}>
            Cancel
          </button>
        </Sheet>
      )}
    </div>
  );
}

function SheetAction({
  icon,
  danger,
  disabled,
  aside,
  onClick,
  children,
}: {
  icon: ReactNode;
  danger?: boolean;
  disabled?: boolean;
  aside?: string;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      className={danger ? 'sheet-action danger' : 'sheet-action'}
      disabled={disabled}
      onClick={onClick}
    >
      {icon}
      {children}
      {aside && <span className="aside">{aside}</span>}
    </button>
  );
}

function CopyAction({ text, onDone }: { text: string; onDone: () => void }) {
  const [copied, setCopied] = useState(false);
  return (
    <SheetAction
      icon={ICONS.copy}
      onClick={() => {
        void navigator.clipboard?.writeText(text).then(() => {
          setCopied(true);
          window.setTimeout(onDone, 700);
        });
      }}
    >
      {copied ? 'Copied' : 'Copy PGN'}
    </SheetAction>
  );
}

function Controls({
  tree,
  path,
  online,
  onGo,
  onFlip,
  onComment,
}: {
  tree: ParsedGame;
  path: MovePath;
  online: boolean;
  onGo: (path: MovePath) => void;
  onFlip: () => void;
  onComment: () => void;
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
      if (target?.closest('input, textarea, select, dialog')) return;
      if (event.key === 'ArrowLeft' && back) onGo(back);
      else if (event.key === 'ArrowRight' && next) onGo(next);
      else return;
      event.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <div className="game-controls">
      <button type="button" className="side" aria-label="Flip board" disabled={!online} onClick={onFlip}>
        {ICONS.flip}
      </button>
      <button type="button" className="end" aria-label="Go to start" disabled={!back} onClick={() => onGo([])}>
        {ICONS.start}
      </button>
      <button type="button" className="step" aria-label="Previous move" disabled={!back}
        onClick={() => back && onGo(back)}>
        {ICONS.previous}
      </button>
      <button type="button" className="step forward" aria-label="Next move" disabled={!next}
        onClick={() => next && onGo(next)}>
        {ICONS.next}
      </button>
      <button type="button" className="end" aria-label="Go to end" disabled={!next} onClick={() => onGo(end())}>
        {ICONS.end}
      </button>
      <button type="button" className="side" aria-label="Comment" disabled={!online} onClick={onComment}>
        {ICONS.comment}
      </button>
    </div>
  );
}

function CommentEditor({
  label,
  value,
  onCancel,
  onSave,
}: {
  /** The move commented on; none for the note on the whole game. */
  label: string | null;
  value: string | undefined;
  onCancel: () => void;
  onSave: (text: string) => void;
}) {
  const [text, setText] = useState(value ?? '');
  return (
    <div className="comment-editor">
      <div className="sheet-heading">
        <h3>{label ? <>Comment after <span className="good-text">{label}</span></> : 'Note on the game'}</h3>
        {value && (
          <button type="button" className="link danger aside" onClick={() => onSave('')}>
            Remove
          </button>
        )}
      </div>
      <textarea
        aria-label={label ? `Comment after ${label}` : 'Note on the game'}
        value={text}
        onChange={(event) => setText(event.target.value)}
        rows={4}
        placeholder="A comment"
        autoFocus
      />
      <div className="sheet-buttons">
        <button type="button" onClick={onCancel}>
          Cancel
        </button>
        <button type="button" className="primary" disabled={text.trim() === (value ?? '')} onClick={() => onSave(text)}>
          Save
        </button>
      </div>
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
        className="primary"
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
