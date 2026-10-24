import { useEffect, useRef } from 'react';
import type { ReactNode } from 'react';
import type { MovePath } from '../../model/games/edit';
import { moveNumber } from '../../model/games/pgn';
import type { MoveNode, ParsedGame } from '../../model/games/pgn';
import { displayComment, NAG_SYMBOLS } from '../../model/games/summary';

interface Props {
  game: ParsedGame;
  path: MovePath;
  onGo: (path: MovePath) => void;
}

/**
 * The moves as they read in a book: the main line runs on, and each variation
 * sits indented beneath the move it is an alternative to, nested as deep as
 * the game goes. Every move is a button that goes to it.
 */
export function MoveList({ game, path, onGo }: Props) {
  const list = useRef<HTMLDivElement>(null);
  const current = path.join('.');

  // Keeps the current move in view as the arrows step through a long game.
  useEffect(() => {
    list.current
      ?.querySelector<HTMLElement>('[data-current]')
      ?.scrollIntoView({ block: 'nearest' });
  }, [current]);

  const move = (node: MoveNode, fen: string, at: MovePath, numbered: boolean): ReactNode => {
    const key = at.join('.');
    const number = moveNumber(fen, numbered || Boolean(node.before));
    const nags = node.nags.map((nag) => NAG_SYMBOLS[nag] ?? '').join('');
    const before = displayComment(node.before);
    const comment = displayComment(node.comment);
    return (
      <span key={key} className="move-item">
        {before && <span className="move-comment">{before}</span>}
        <button
          type="button"
          className="move"
          data-current={key === current || undefined}
          onClick={() => onGo(at)}
        >
          {number && <span className="move-number">{number} </span>}
          {node.san}
          {nags}
        </button>
        {comment && <span className="move-comment">{comment}</span>}
      </span>
    );
  };

  /** `list[0]` and on, with `list[1..]` as variations under it. */
  const line = (nodes: MoveNode[], fen: string, at: MovePath, numbered: boolean): ReactNode[] => {
    const out: ReactNode[] = [];
    while (nodes.length) {
      const [main, ...alternatives] = nodes;
      out.push(move(main, fen, [...at, 0], numbered));
      numbered = Boolean(main.comment);
      if (alternatives.length) {
        out.push(
          <div key={`${[...at, 0].join('.')}-variations`} className="variations">
            {alternatives.map((alternative, index) => {
              const here = [...at, index + 1];
              return (
                <div key={here.join('.')} className="variation">
                  {move(alternative, fen, here, true)}
                  {line(alternative.children, alternative.fen, here, Boolean(alternative.comment))}
                </div>
              );
            })}
          </div>,
        );
        numbered = true;
      }
      fen = main.fen;
      nodes = main.children;
      at = [...at, 0];
    }
    return out;
  };

  const note = displayComment(game.comment);

  return (
    <div className="move-list" ref={list}>
      <button
        type="button"
        className="move start"
        data-current={current === '' || undefined}
        onClick={() => onGo([])}
      >
        Start
      </button>
      {note && <span className="move-comment">{note}</span>}
      {line(game.moves, game.startFen, [], true)}
      {!game.moves.length && <span className="muted small"> No moves yet.</span>}
    </div>
  );
}
