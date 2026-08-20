import { firstIllegalMove, setupMoveIsLegal } from '../board';
import { parseUci } from '../move';
import type { Uci } from '../move';
import { contentKey } from '../puzzle';
import type { Puzzle } from '../puzzle';
import { isPlausibleFen } from './json';
import type { ImportResult } from './json';

/**
 * Adapter for the public Lichess puzzle database dump.
 *
 * Columns: `PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags`
 *
 * The dump's convention is that `FEN` is the position one ply *before* the
 * puzzle starts, and the first entry in `Moves` is the opponent's move into it.
 * That maps onto `Puzzle.setupMove`, so no FEN arithmetic is needed here — which
 * matters, because doing it properly would drag a full move generator into the
 * importer.
 */
export interface LichessImportOptions {
  /**
   * Keep only puzzles inside this rating band. The dump is four million rows
   * wide; importing it unfiltered is never what you want.
   */
  ratingRange?: [number, number];
  /** Keep only puzzles carrying at least one of these themes. */
  themes?: Set<string>;
  /** Stop after this many accepted puzzles. */
  limit?: number;
}

export function importLichessCsv(
  text: string,
  options: LichessImportOptions = {},
  existingKeys = new Set<string>(),
): ImportResult {
  const result: ImportResult = { groups: [], inserted: [], updated: [], rejected: [] };
  const seen = new Set(existingKeys);
  const lines = text.split('\n');

  for (let index = 0; index < lines.length; index++) {
    if (options.limit !== undefined && result.inserted.length >= options.limit) break;

    const line = lines[index].replace(/\r$/, '');
    if (!line.trim()) continue;

    const fields = line.split(',');
    if (fields.length < 3) {
      result.rejected.push({ index, reason: 'Too few columns' });
      continue;
    }

    const fen = fields[1];
    if (!isPlausibleFen(fen)) {
      // Silently skip a header row; report anything else.
      if (index > 0) result.rejected.push({ index, reason: 'Malformed FEN' });
      continue;
    }

    const moves: Uci[] = [];
    let malformed = false;
    for (const token of fields[2].split(' ')) {
      if (!token) continue;
      const move = parseUci(token);
      if (!move) {
        malformed = true;
        break;
      }
      moves.push(move);
    }
    if (malformed) {
      result.rejected.push({ index, reason: 'Malformed move in solution' });
      continue;
    }
    if (moves.length < 2) {
      result.rejected.push({ index, reason: 'Needs a setup move and at least one solver move' });
      continue;
    }

    const solution = moves.slice(1);
    if (solution.length % 2 !== 1) {
      result.rejected.push({ index, reason: 'Solution line ends on an opponent move' });
      continue;
    }

    if (!setupMoveIsLegal(fen, moves[0])) {
      result.rejected.push({ index, reason: `Setup move ${moves[0]} is illegal in this position` });
      continue;
    }
    const illegal = firstIllegalMove(fen, moves[0], [solution]);
    if (illegal) {
      result.rejected.push({
        index,
        reason: `Move ${illegal.move} is illegal at ply ${illegal.ply + 1}`,
      });
      continue;
    }

    const rating = fields.length > 3 ? Number(fields[3]) : NaN;
    if (options.ratingRange) {
      const [low, high] = options.ratingRange;
      if (!Number.isFinite(rating) || rating < low || rating > high) continue;
    }

    const themes = fields.length > 7 && fields[7] ? fields[7].split(' ').filter(Boolean) : [];
    if (options.themes && !themes.some((theme) => options.themes!.has(theme))) continue;

    const puzzle: Puzzle = {
      id: crypto.randomUUID(),
      fen,
      setupMove: moves[0],
      solutions: [solution],
      tags: themes,
      sourceId: fields[0] || undefined,
      rating: Number.isFinite(rating) ? rating : undefined,
      addedAt: Date.now(),
    };

    const key = contentKey(puzzle);
    if (seen.has(key)) {
      result.updated.push(puzzle);
    } else {
      seen.add(key);
      result.inserted.push(puzzle);
    }
  }

  // The dump has no chapters, so everything lands in one unnamed group and
  // the import screen supplies a name.
  result.groups.push({ puzzles: [...result.inserted, ...result.updated] });
  return result;
}
