import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import type { MovePath } from '../../model/games/edit';
import { moveNumber } from '../../model/games/pgn';
import type { MoveNode, ParsedGame } from '../../model/games/pgn';
import { displayComment, NAG_SYMBOLS } from '../../model/games/summary';
import { lineLength, moveTable, startsWith } from '../../model/games/table';

/** A variation longer than this starts folded, unless you are somewhere in it. */
const LONG_LINE = 6;
/** How much of a folded variation still shows. */
const FOLDED_SHOWS = 5;

interface Props {
  game: ParsedGame;
  path: MovePath;
  onGo: (path: MovePath) => void;
  /** A long press (or right click) on a move: what can be done with it. */
  onHold: (path: MovePath) => void;
}

export function hasComment(node: MoveNode): boolean {
  return Boolean(displayComment(node.comment) || displayComment(node.before));
}

/** Marks a move with a comment; the comment itself shows above the list. */
function CommentMark() {
  return (
    <svg className="has-comment" role="img" aria-label="has a comment" width="13" height="13" viewBox="0 0 24 24">
      <path d="M4 4h16v12H9l-5 4V4z" fill="currentColor" />
    </svg>
  );
}

/** A move that goes to itself on a tap, and offers what can be done with it on a long press. */
function MoveButton({
  className,
  current,
  onGo,
  onHold,
  children,
}: {
  className: string;
  current: boolean;
  onGo: () => void;
  onHold: () => void;
  children: ReactNode;
}) {
  const timer = useRef(0);
  const origin = useRef<[number, number] | null>(null);
  const held = useRef(false);

  const stop = () => {
    window.clearTimeout(timer.current);
    origin.current = null;
  };
  const hold = () => {
    stop();
    held.current = true;
    onHold();
  };

  return (
    <button
      type="button"
      className={className}
      aria-current={current || undefined}
      onPointerDown={(event) => {
        held.current = false;
        origin.current = [event.clientX, event.clientY];
        timer.current = window.setTimeout(hold, 500);
      }}
      // A finger that moves is scrolling, not holding.
      onPointerMove={(event) => {
        const from = origin.current;
        if (from && Math.hypot(event.clientX - from[0], event.clientY - from[1]) > 10) stop();
      }}
      onPointerUp={stop}
      onPointerCancel={stop}
      onPointerLeave={stop}
      onContextMenu={(event) => {
        event.preventDefault();
        hold();
      }}
      onClick={() => {
        if (held.current) held.current = false;
        else onGo();
      }}
    >
      {children}
    </button>
  );
}

/**
 * The main line as a table, a row per move number, with each move's
 * alternatives set in an indented panel straight after its row. Variations
 * read as text inside their panel, and fold away when they run long.
 */
export function MoveList({ game, path, onGo, onHold }: Props) {
  const list = useRef<HTMLDivElement>(null);
  const current = path.join('.');
  // Variations opened or folded by hand, by where they start.
  const [folding, setFolding] = useState<Map<string, boolean>>(new Map());

  // Keeps the current move in view as the arrows step through a long game.
  useEffect(() => {
    const at = list.current?.querySelector<HTMLElement>('[aria-current]');
    if (at) at.scrollIntoView({ block: 'nearest' });
    else if (current === '') list.current?.scrollTo({ top: 0 });
  }, [current]);

  const label = (node: MoveNode, number: string | null) => (
    <>
      {number && <span className="move-number">{number} </span>}
      {node.san}
      {node.nags.map((nag) => NAG_SYMBOLS[nag] ?? '').join('')}
      {hasComment(node) && <CommentMark />}
    </>
  );

  const button = (className: string, node: MoveNode, at: MovePath, number: string | null) => (
    <MoveButton
      key={at.join('.')}
      className={className}
      current={at.join('.') === current}
      onGo={() => onGo(at)}
      onHold={() => onHold(at)}
    >
      {label(node, number)}
    </MoveButton>
  );

  /** A variation: `first` and the line it starts, with its own alternatives nested inside. */
  const variation = (first: MoveNode, fen: string, at: MovePath): ReactNode => {
    const key = at.join('.');
    const length = lineLength(first);
    const long = length > LONG_LINE;
    const open = folding.get(key) ?? (!long || startsWith(path, at));
    const fold = (to: boolean) => setFolding((map) => new Map(map).set(key, to));

    // Each move, then the alternatives to it, as PGN writes them.
    const out: ReactNode[] = [];
    let siblings: MoveNode[] = [first];
    let before = fen;
    let parent = at.slice(0, -1);
    let here = at;
    let numbered = true;
    for (let shown = 0; siblings.length && (open || shown < FOLDED_SHOWS); shown++) {
      const [node, ...alternatives] = siblings;
      out.push(button('var-move', node, here, moveNumber(before, numbered)));
      numbered = false;
      if (open && alternatives.length) {
        alternatives.forEach((alternative, index) =>
          out.push(variation(alternative, before, [...parent, index + 1])),
        );
        numbered = true;
      }
      before = node.fen;
      parent = here;
      here = [...here, 0];
      siblings = node.children;
    }

    return (
      <div key={key} className="var">
        {out}
        {!open && (
          <button type="button" className="var-toggle" aria-expanded={false} onClick={() => fold(true)}>
            +{length - FOLDED_SHOWS} moves
          </button>
        )}
        {open && long && (
          <button type="button" className="var-toggle fold" aria-expanded onClick={() => fold(false)}>
            Fold
          </button>
        )}
      </div>
    );
  };

  const items = moveTable(game);
  let rows = 0;

  return (
    <div className="game-moves" ref={list}>
      {items.map((item, index) => {
        if (item.kind === 'variations') {
          return (
            <div key={`v${index}`} className="variations">
              {item.alternatives.map((cell) => variation(cell.node, item.fen, cell.path))}
            </div>
          );
        }
        const brokenAfter = items[index + 1]?.kind === 'variations';
        return (
          <div key={`r${index}`} className="move-row" data-odd={rows++ % 2 === 1 || undefined}>
            <span className="move-no">{item.number}.</span>
            {item.white ? (
              button('move-cell', item.white.node, item.white.path, null)
            ) : (
              <span className="move-cell gap">…</span>
            )}
            {item.black ? (
              button('move-cell', item.black.node, item.black.path, null)
            ) : (
              <span className="move-cell gap">{brokenAfter ? '…' : ''}</span>
            )}
          </div>
        );
      })}
      {!items.length && <p className="muted small no-moves">No moves yet. Play one on the board.</p>}
    </div>
  );
}
