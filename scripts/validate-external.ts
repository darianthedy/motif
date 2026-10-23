/**
 * Validates an external puzzle file against the rules of chess.
 *
 * Everything the importer checks, it checks the same way, by running the
 * importer. On top of that it audits what the importer cannot know: a
 * mate-in-N puzzle must mate in exactly N, or the position was misread or the
 * move was; and a missing-piece puzzle must have exactly one right answer, or
 * a correct one will be marked wrong.
 *
 * Usage: npm run check:external -- <file.json>
 */
import { readFileSync } from 'node:fs';
import { isCheckmate, matingPlacements, replayLine } from '../src/model/board';
import { importJson } from '../src/model/import/json';
import { placementText } from '../src/model/puzzle';
import type { PuzzleContent } from '../src/model/puzzle';

/** What the importer cannot see, or null when there is nothing to say. */
function audit(puzzle: PuzzleContent): string | null {
  const mateTag = puzzle.tags.find((tag) => /^mateIn\d$/.test(tag));

  if (puzzle.addPiece) {
    const answer = placementText(puzzle.addPiece);
    const mates = matingPlacements(puzzle.fen, puzzle.addPiece.color).map(placementText);
    // Not every missing-piece puzzle is a mate, so this is only worth saying
    // when the puzzle claims to be one.
    if (!mates.includes(answer)) return mateTag ? `${answer} is not mate` : null;
    if (mates.length > 1) return `ambiguous: ${mates.join(', ')} all mate`;
    return null;
  }

  if (!mateTag) return null;
  const n = Number(mateTag.slice('mateIn'.length));
  const line = puzzle.solutions[0];
  if (line.length !== n * 2 - 1) return `${mateTag} but solution is ${line.length} plies`;
  const final = replayLine(puzzle.fen, line).at(-1)?.fen;
  return final && isCheckmate(final) ? null : `${mateTag} but final position is not mate`;
}

const path = process.argv[2];
if (!path) {
  console.log('Usage: npm run check:external -- <file.json>');
  process.exit(2);
}
const text = readFileSync(path, 'utf8');
const result = importJson(text);

// The importer reports rejections by their index across the whole file.
const parsed = JSON.parse(text) as unknown;
const blocks = (Array.isArray(parsed) ? parsed : [parsed]) as {
  collection?: string;
  puzzles?: { id?: unknown }[];
}[];
const labels = blocks.flatMap((block) =>
  (block.puzzles ?? []).map((entry) => `${block.collection} #${String(entry.id)}`),
);

const problems: [string, string][] = result.rejected.map((reject) => [
  labels[reject.index] ?? 'file',
  reject.reason,
]);
for (const group of result.groups) {
  for (const puzzle of group.puzzles) {
    const problem = audit(puzzle);
    if (problem) problems.push([`${group.name} #${puzzle.sourceId}`, problem]);
  }
}

console.log(`${labels.length} puzzles in ${blocks.length} collection(s)`);
console.log(`${labels.length - problems.length} valid, ${problems.length} problems`);
for (const [label, reason] of problems.slice(0, 25)) console.log(`  ${label}: ${reason}`);
if (problems.length > 25) console.log(`  …and ${problems.length - 25} more`);
process.exit(problems.length ? 1 : 0);
