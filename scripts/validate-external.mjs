/**
 * Validates an external puzzle file against the rules of chess.
 *
 * Mate-in-N puzzles audit their own FEN: if the stated solution does not
 * deliver mate in exactly N, either the position was misread or the move was.
 */
import { readFileSync } from 'node:fs';
import { Chess } from 'chess.js';

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
