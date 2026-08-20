import { useCallback, useEffect, useRef, useState } from 'react';
import { needsPromotion, piecesOn, SQUARES, targetsFrom } from '../model/board';
import type { PieceType, Target } from '../model/board';
import { makeMove } from '../model/move';
import type { PromotionPiece, Uci } from '../model/move';
import type { Side } from '../model/puzzle';
import './Board.css';

/**
 * Solid glyphs for both colours, tinted rather than mixing the outline and
 * filled sets. The outline glyphs are noticeably lighter than the filled ones
 * in most system fonts, so a mixed board looks unbalanced at small sizes.
 */
const GLYPH: Record<PieceType, string> = {
  k: '♚',
  q: '♛',
  r: '♜',
  b: '♝',
  n: '♞',
  p: '♟',
};

const PROMOTION_CHOICES: PromotionPiece[] = ['q', 'r', 'b', 'n'];

interface PendingPromotion {
  from: string;
  to: string;
}

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

/**
 * The board. Owns selection, dragging and the promotion picker.
 *
 * Tap and drag are not two code paths: a pointer press selects, a pointer
 * release decides. Releasing on the square you pressed leaves the piece
 * selected, which is a tap; releasing on a legal destination commits, which is
 * a drag. Both end in the same `onMove` call with the same UCI string, so the
 * validator upstream cannot tell them apart — and neither can the scoring.
 *
 * Anything that does not produce a legal move — releasing on an illegal square,
 * off the board, or cancelling the promotion picker — resolves to a deselect
 * and never reaches `onMove`. That is what keeps a mis-drag free.
 */
export function Board({
  fen,
  orientation,
  onMove,
  highlight,
  shakeKey,
  interactive = true,
}: BoardProps) {
  const [selected, setSelected] = useState<string | null>(null);
  const [targets, setTargets] = useState<Map<string, Target>>(new Map());
  const [pending, setPending] = useState<PendingPromotion | null>(null);
  const [drag, setDrag] = useState<{ from: string; x: number; y: number } | null>(null);
  const boardRef = useRef<HTMLDivElement>(null);

  const pieces = piecesOn(fen);
  const pieceAt = new Map(pieces.map((piece) => [piece.square, piece]));
  const files = orientation === 'w' ? 'abcdefgh' : 'hgfedcba';
  const ranks = orientation === 'w' ? [8, 7, 6, 5, 4, 3, 2, 1] : [1, 2, 3, 4, 5, 6, 7, 8];

  // Any change of position abandons whatever was in flight. Without this a
  // selection can survive into the next puzzle and point at a square whose
  // piece is gone.
  useEffect(() => {
    setSelected(null);
    setTargets(new Map());
    setPending(null);
    setDrag(null);
  }, [fen]);

  const select = useCallback(
    (square: string) => {
      setSelected(square);
      setTargets(targetsFrom(fen, square));
    },
    [fen],
  );

  const clear = useCallback(() => {
    setSelected(null);
    setTargets(new Map());
    setDrag(null);
  }, []);

  /** Commits, or opens the picker first when the destination needs one. */
  const commit = useCallback(
    (from: string, to: string) => {
      if (needsPromotion(fen, from, to)) {
        setPending({ from, to });
        setDrag(null);
        return;
      }
      clear();
      onMove(makeMove(from, to));
    },
    [clear, fen, onMove],
  );

  /** Which square a client coordinate falls on, or null if off the board. */
  const squareAt = useCallback(
    (clientX: number, clientY: number): string | null => {
      const rect = boardRef.current?.getBoundingClientRect();
      if (!rect) return null;
      const col = Math.floor(((clientX - rect.left) / rect.width) * 8);
      const row = Math.floor(((clientY - rect.top) / rect.height) * 8);
      if (col < 0 || col > 7 || row < 0 || row > 7) return null;
      return `${files[col]}${ranks[row]}`;
    },
    [files, ranks],
  );

  const onPointerDown = (event: React.PointerEvent) => {
    if (!interactive || pending) return;
    const square = squareAt(event.clientX, event.clientY);
    if (!square) return;

    // Committing on press would make a drag impossible, so a press on a legal
    // destination only records intent; the release decides.
    if (selected && targets.has(square)) {
      commit(selected, square);
      return;
    }

    const piece = pieceAt.get(square);
    if (piece) {
      // Tapping a different piece of yours reselects rather than counting as a
      // move to an illegal square.
      select(square);
      setDrag({ from: square, x: event.clientX, y: event.clientY });
      boardRef.current?.setPointerCapture(event.pointerId);
    } else {
      clear();
    }
  };

  const onPointerMove = (event: React.PointerEvent) => {
    if (!drag) return;
    setDrag({ ...drag, x: event.clientX, y: event.clientY });
  };

  const onPointerUp = (event: React.PointerEvent) => {
    if (!drag) return;
    const square = squareAt(event.clientX, event.clientY);
    boardRef.current?.releasePointerCapture(event.pointerId);

    // Released where it started: a tap. Keep the selection so the next tap can
    // choose a destination.
    if (square === drag.from) {
      setDrag(null);
      return;
    }

    if (square && targets.has(square)) {
      commit(drag.from, square);
      return;
    }

    // Off-board or an illegal square. Free — this is the mis-drag case.
    clear();
  };

  const choosePromotion = (piece: PromotionPiece) => {
    if (!pending) return;
    const { from, to } = pending;
    setPending(null);
    clear();
    onMove(makeMove(from, to, piece));
  };

  return (
    <div className="board-wrap">
      <div
        ref={boardRef}
        className="board"
        key={shakeKey}
        data-shake={shakeKey ? 'yes' : undefined}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={clear}
      >
        {ranks.map((rank, row) =>
          files.split('').map((file, col) => {
            const square = `${file}${rank}`;
            const piece = pieceAt.get(square);
            const target = targets.get(square);
            const dark = (row + col) % 2 === 1;
            const isDragging = drag?.from === square;

            return (
              <div
                key={square}
                className="square"
                data-dark={dark || undefined}
                data-selected={selected === square || undefined}
                data-highlight={
                  highlight && (highlight.from === square || highlight.to === square)
                    ? 'yes'
                    : undefined
                }
              >
                {piece && (
                  <span
                    className="piece"
                    data-color={piece.color}
                    data-ghost={isDragging || undefined}
                  >
                    {GLYPH[piece.type]}
                  </span>
                )}
                {target && <span className="target" data-capture={target.capture || undefined} />}
              </div>
            );
          }),
        )}
      </div>

      {/* The dragged piece follows the pointer outside the grid flow, so it is
          never clipped by a square and never intercepts its own hit testing. */}
      {drag && pieceAt.get(drag.from) && (
        <span
          className="piece dragging"
          data-color={pieceAt.get(drag.from)!.color}
          style={{ left: drag.x, top: drag.y }}
        >
          {GLYPH[pieceAt.get(drag.from)!.type]}
        </span>
      )}

      {pending && (
        <div className="promotion-backdrop" onPointerDown={() => setPending(null)}>
          <div className="promotion" onPointerDown={(event) => event.stopPropagation()}>
            {PROMOTION_CHOICES.map((choice) => (
              <button key={choice} type="button" onClick={() => choosePromotion(choice)}>
                <span className="piece" data-color={orientation}>
                  {GLYPH[choice]}
                </span>
              </button>
            ))}
            <button type="button" className="promotion-cancel" onClick={() => setPending(null)}>
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export { SQUARES };
