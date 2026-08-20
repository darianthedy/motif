import { useCallback, useEffect, useMemo, useState } from 'react';
import type { Square } from 'chess.js';
import { Chessboard } from 'react-chessboard';
import type { PieceDropHandlerArgs, SquareHandlerArgs } from 'react-chessboard';
import { needsPromotion, targetsFrom, turnOf } from '../model/board';
import { makeMove } from '../model/move';
import type { PromotionPiece, Uci } from '../model/move';
import type { Side } from '../model/puzzle';
import './Board.css';

/**
 * react-chessboard supplies the piece set and the drag layer.
 *
 * The first version drew the board by hand with Unicode glyphs, which looked
 * acceptable in Chromium and poor on iOS: the system chess glyphs are heavy and
 * detail-free at board size, and U+265F additionally defaults to an emoji
 * presentation. Fonts were the wrong dependency for something that has to look
 * the same everywhere — vector pieces are.
 *
 * What did not change is where the rules live. This component still resolves
 * every interaction to a UCI string and hands it up; the runner still cannot
 * tell a tap from a drag; an interaction that fails to produce a legal move
 * still never reaches it.
 */

const SELECTED_STYLE: React.CSSProperties = {
  background: 'rgba(255, 213, 79, 0.55)',
};

const HIGHLIGHT_STYLE: React.CSSProperties = {
  background: 'rgba(93, 168, 255, 0.45)',
};

// A dot for a quiet move, a ring for a capture, so a destination reads
// differently when something is standing on it.
const MOVE_DOT_STYLE: React.CSSProperties = {
  background: 'radial-gradient(circle, rgba(20,20,20,0.28) 18%, transparent 20%)',
};

const CAPTURE_RING_STYLE: React.CSSProperties = {
  background:
    'radial-gradient(circle, transparent 54%, rgba(20,20,20,0.28) 56%, rgba(20,20,20,0.28) 66%, transparent 68%)',
};

const PROMOTION_CHOICES: PromotionPiece[] = ['q', 'r', 'b', 'n'];

const PROMOTION_GLYPH: Record<PromotionPiece, string> = {
  q: 'Queen',
  r: 'Rook',
  b: 'Bishop',
  n: 'Knight',
};

export interface BoardProps {
  fen: string;
  orientation: Side;
  /** Called only with moves already verified legal against `fen`. */
  onMove: (move: Uci) => void;
  /** Squares to mark, e.g. a revealed hint or the move just played. */
  highlight?: { from: string; to: string } | null;
  /** Changing this value replays the "wrong move" shake. */
  shakeKey?: number;
  interactive?: boolean;
}

export function Board({
  fen,
  orientation,
  onMove,
  highlight,
  shakeKey,
  interactive = true,
}: BoardProps) {
  const [selected, setSelected] = useState<string | null>(null);
  const [pending, setPending] = useState<{ from: string; to: string } | null>(null);

  const turn = turnOf(fen);
  const targets = useMemo(
    () => (selected ? targetsFrom(fen, selected) : new Map()),
    [fen, selected],
  );

  // A new position abandons whatever was in flight. Without this a selection
  // can survive into the next puzzle and point at a square whose piece is gone.
  useEffect(() => {
    setSelected(null);
    setPending(null);
  }, [fen]);

  /**
   * Resolves an interaction into a move, or into nothing.
   *
   * Returns whether the board should treat the move as accepted. Illegal
   * destinations return false, which snaps a dragged piece back and costs the
   * solver nothing — the runner never hears about it.
   */
  const play = useCallback(
    (from: string, to: string): boolean => {
      if (!interactive) return false;
      if (!targetsFrom(fen, from).has(to)) return false;

      setSelected(null);
      if (needsPromotion(fen, from, to)) {
        // Held rather than played: the picker decides which piece, and
        // cancelling it is the same as never having moved.
        setPending({ from, to });
        return false;
      }
      onMove(makeMove(from, to));
      return true;
    },
    [fen, interactive, onMove],
  );

  const onPieceDrop = useCallback(
    ({ sourceSquare, targetSquare }: PieceDropHandlerArgs): boolean => {
      setSelected(null);
      if (!targetSquare) return false;
      return play(sourceSquare, targetSquare);
    },
    [play],
  );

  // Square clicks alone: pieces render inside squares and do not stop
  // propagation, so one handler covers occupied and empty squares, with `piece`
  // telling them apart. Adding onPieceClick would double-fire.
  const onSquareClick = useCallback(
    ({ piece, square }: SquareHandlerArgs) => {
      if (!interactive) return;
      const isOwnPiece = piece ? piece.pieceType[0] === turn : false;

      if (!selected) {
        if (isOwnPiece) setSelected(square);
        return;
      }
      if (square === selected) {
        setSelected(null);
        return;
      }
      if (targets.has(square)) {
        play(selected, square);
        return;
      }
      // Tapping another of your own pieces re-targets rather than counting as
      // a move to an illegal square.
      setSelected(isOwnPiece ? square : null);
    },
    [interactive, play, selected, targets, turn],
  );

  const squareStyles = useMemo(() => {
    const styles: Record<string, React.CSSProperties> = {};
    if (highlight) {
      styles[highlight.from] = { ...HIGHLIGHT_STYLE };
      styles[highlight.to] = { ...HIGHLIGHT_STYLE };
    }
    if (selected) {
      styles[selected] = { ...styles[selected], ...SELECTED_STYLE };
      for (const [target, info] of targets) {
        styles[target] = {
          ...styles[target],
          ...(info.capture ? CAPTURE_RING_STYLE : MOVE_DOT_STYLE),
        };
      }
    }
    return styles;
  }, [highlight, selected, targets]);

  const choosePromotion = (piece: PromotionPiece) => {
    if (!pending) return;
    const { from, to } = pending;
    setPending(null);
    onMove(makeMove(from, to, piece));
  };

  return (
    <div className="board-wrap" data-shake={shakeKey || undefined} key={shakeKey}>
      <Chessboard
        options={{
          id: 'motif-board',
          position: fen,
          onPieceDrop,
          onSquareClick,
          squareStyles,
          boardOrientation: orientation === 'w' ? 'white' : 'black',
          allowDragging: interactive,
          animationDurationInMs: 150,
        }}
      />

      {pending && (
        <div className="promotion-backdrop" onClick={() => setPending(null)}>
          <div className="promotion" onClick={(event) => event.stopPropagation()}>
            <p className="promotion-title">Promote to</p>
            {PROMOTION_CHOICES.map((choice) => (
              <button key={choice} type="button" onClick={() => choosePromotion(choice)}>
                {PROMOTION_GLYPH[choice]}
              </button>
            ))}
            <button type="button" className="link" onClick={() => setPending(null)}>
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export type { Square };
