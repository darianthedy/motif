/**
 * Validates an external puzzle file against the rules of chess.
 *
 * Mate-in-N puzzles audit their own FEN: if the stated solution does not
 * deliver mate in exactly N, either the position was misread or the move was.
 */
import { readFileSync } from 'node:fs';
import { Chess } from 'chess.js';

const FILES = 'abcdefgh';
const PLACEMENT_RE = /^(?:([wb])[\s-]*)?([pnbrqkPNBRQK])[\s-]*([a-h][1-8])$/;

function parsePlacement(text) {
  const match = typeof text === 'string' ? PLACEMENT_RE.exec(text.trim()) : null;
  if (!match) return null;
  const [, prefix, piece, square] = match;
  return {
    color: prefix ?? (piece === piece.toUpperCase() ? 'w' : 'b'),
    type: piece.toLowerCase(),
    square,
  };
}

const written = (p) => `${p.color === 'w' ? p.type.toUpperCase() : p.type}${p.square}`;

/** The position with a piece added, or null if that is not a position. */
function place(fen, placement) {
  const rank = Number(placement.square[1]);
  if (placement.type === 'p' && (rank === 1 || rank === 8)) return null;
  try {
    const chess = new Chess(fen);
    if (chess.get(placement.square)) return null;
    if (!chess.put({ type: placement.type, color: placement.color }, placement.square)) return null;
    const next = chess.fen();
    new Chess(next);
    return next;
  } catch {
    return null;
  }
}

/** Every piece and square of one colour that would mate the side to move. */
function matingPlacements(fen, color) {
  const found = [];
  for (const file of FILES) {
    for (let rank = 1; rank <= 8; rank++) {
      for (const type of ['q', 'r', 'b', 'n', 'p']) {
        const placement = { color, type, square: `${file}${rank}` };
        const next = place(fen, placement);
        if (!next) continue;
        try {
          if (new Chess(next).isCheckmate()) found.push(written(placement));
        } catch {
          // Not a position that loads, so not a candidate.
        }
      }
    }
  }
  return found;
}

/**
 * Audits one missing-piece puzzle.
 *
 * The ambiguity check is the one that matters: the puzzle accepts a single
 * placement, so a position where two different pieces both mate will mark a
 * correct answer wrong. That is not something a solver could ever diagnose.
 */
function checkPlacement(chess, puzzle, raw) {
  const placement = parsePlacement(raw);
  if (!placement) return `unreadable add_piece: ${JSON.stringify(raw)}`;
  if (placement.type === 'k') return 'add_piece is a king';
  if (puzzle.solutions?.length) return 'has both add_piece and solutions';
  if (chess.get(placement.square)) return `${placement.square} is not empty`;

  const placed = place(chess.fen(), placement);
  if (!placed) return `${written(placement)} does not make a legal position`;

  const mates = matingPlacements(chess.fen(), placement.color);
  if (!mates.includes(written(placement))) {
    // Not every missing-piece puzzle is a mate, so this is only worth saying
    // when the puzzle claims to be one.
    const claimsMate = (puzzle.tags ?? []).some((t) => t.startsWith('mateIn'));
    return claimsMate ? `${written(placement)} is not mate` : null;
  }
  if (mates.length > 1) return `ambiguous: ${mates.join(', ')} all mate`;
  return null;
}

const path = process.argv[2];
const raw = JSON.parse(readFileSync(path, 'utf8'));
const groups = Array.isArray(raw) ? raw : [raw];

let total = 0;
const problems = [];

for (const group of groups) {
  for (const puzzle of group.puzzles ?? []) {
    total++;
    const label = `${group.collection} #${puzzle.id}`;
    let chess;
    try {
      chess = new Chess(puzzle.fen);
    } catch (error) {
      problems.push([label, `unloadable FEN: ${error.message}`]);
      continue;
    }

    // A missing-piece puzzle answers with a placement instead of a line, and is
    // audited differently: the question is whether the piece can go there at
    // all, and whether it is the *only* piece that would do.
    const addPiece = puzzle.add_piece ?? puzzle.addPiece;
    if (addPiece !== undefined) {
      const problem = checkPlacement(chess, puzzle, addPiece);
      if (problem) problems.push([label, problem]);
      continue;
    }

    const line = puzzle.solutions?.[0];
    if (!line?.length) {
      problems.push([label, 'no solution']);
      continue;
    }

    let illegal = null;
    for (const move of line) {
      try {
        const played = chess.move({
          from: move.slice(0, 2),
          to: move.slice(2, 4),
          promotion: move[4] || undefined,
        });
        if (!played) { illegal = move; break; }
      } catch {
        illegal = move;
        break;
      }
    }
    if (illegal) {
      problems.push([label, `illegal move ${illegal} in ${puzzle.fen}`]);
      continue;
    }

    const mateTag = (puzzle.tags ?? []).find((t) => /^mateIn(\d)$/.test(t));
    if (mateTag) {
      const n = Number(mateTag.slice(6));
      const plies = line.length;
      if (plies !== n * 2 - 1) {
        problems.push([label, `${mateTag} but solution is ${plies} plies`]);
      } else if (!chess.isCheckmate()) {
        problems.push([label, `${mateTag} but final position is not mate`]);
      }
    }
  }
}

console.log(`${total} puzzles in ${groups.length} collection(s)`);
console.log(`${total - problems.length} valid, ${problems.length} problems`);
for (const [label, reason] of problems.slice(0, 25)) console.log(`  ${label}: ${reason}`);
if (problems.length > 25) console.log(`  …and ${problems.length - 25} more`);
