import type { Attempt, Run } from '../data/backend';
import type { PuzzleStatus } from './puzzle';
import { MAX_RETRIES, RECENT_MEMORY, RETRY_GAP } from './session';

/**
 * Everything about progress, worked out from attempts.
 *
 * Nothing here is stored. Attempts are the only record of play, so the status
 * of a puzzle, its counts, the review set and where a run has got to can never
 * disagree with each other or with another device: they are all read from the
 * same rows.
 */

/** Oldest first; the id breaks ties so every device reads the same order. */
function chronological(attempts: Attempt[]): Attempt[] {
  return [...attempts].sort(
    (a, b) => a.playedAt - b.playedAt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  );
}

export interface PuzzleRecord {
  /** The latest result that wasn't a skip. */
  status: PuzzleStatus;
  /** Attempts that were played, skips excluded. */
  attempts: number;
  /** Wrong moves across every attempt. */
  mistakes: number;
  /** When it was last served, skips included. */
  lastPlayedAt: number;
}

/** Keyed by puzzle id. A puzzle with no attempts has no entry and is unseen. */
export function puzzleRecords(attempts: Attempt[]): Map<string, PuzzleRecord> {
  const records = new Map<string, PuzzleRecord>();
  for (const attempt of chronological(attempts)) {
    const record = records.get(attempt.puzzleId) ?? {
      status: 'unseen',
      attempts: 0,
      mistakes: 0,
      lastPlayedAt: attempt.playedAt,
    };
    record.lastPlayedAt = attempt.playedAt;
    if (attempt.result !== 'skipped') {
      record.status = attempt.result;
      record.attempts++;
      record.mistakes += attempt.mistakes;
    }
    records.set(attempt.puzzleId, record);
  }
  return records;
}

export function statusOf(records: Map<string, PuzzleRecord>, puzzleId: string): PuzzleStatus {
  return records.get(puzzleId)?.status ?? 'unseen';
}

/** Of `puzzleIds`, in order, the ones whose latest result is a failure. */
export function reviewIds(puzzleIds: string[], records: Map<string, PuzzleRecord>): string[] {
  return puzzleIds.filter((id) => statusOf(records, id) === 'failed');
}

/**
 * Recently served puzzles, most recent first, for biasing the library-wide
 * draw away from what was just seen.
 */
export function recentIds(attempts: Attempt[]): string[] {
  return [...puzzleRecords(attempts)]
    .sort(([a, x], [b, y]) => y.lastPlayedAt - x.lastPlayedAt || (a < b ? -1 : 1))
    .slice(0, RECENT_MEMORY)
    .map(([id]) => id);
}

export interface Stats {
  total: number;
  solved: number;
  failed: number;
  unseen: number;
}

export function statsFor(puzzleIds: string[], records: Map<string, PuzzleRecord>): Stats {
  const stats: Stats = { total: puzzleIds.length, solved: 0, failed: 0, unseen: 0 };
  for (const id of puzzleIds) stats[statusOf(records, id)]++;
  return stats;
}

export interface RunProgress {
  /** The run's queue, less the puzzles deleted since it started. */
  queue: string[];
  /** The puzzle to serve next, or null when the run is over. */
  current: string | null;
  /** Puzzles still to serve, retries included, the current one too. */
  remaining: number;
  /** Attempts made in the run, skips included. */
  played: number;
  /** Puzzles solved cleanly at some point in the run. */
  solved: number;
  /** Puzzles failed at some point in the run, including ones later retried clean. */
  failed: number;
  /**
   * Fraction of the queue solved, 0–1. Measured against the queue rather than
   * everything served, so a retry never makes the bar slip backwards.
   */
  progress: number;
}

interface Retry {
  puzzleId: string;
  /** Serve once this many puzzles have been completed. */
  readyAt: number;
}

/**
 * Where a run has got to, replaying its attempts in the order they were made.
 *
 * A puzzle is finished once it is solved, skipped, or failed and retried. A
 * miss comes back once, after `RETRY_GAP` other puzzles, while fewer than
 * `MAX_RETRIES` are waiting; due retries are served ahead of fresh puzzles, and
 * once the fresh ones run out the rest are served early rather than left owed.
 *
 * Attempts from two devices in the same run simply interleave: whichever
 * puzzle each of them played counts, so the worst case is a puzzle served
 * twice.
 */
export function runProgress(run: Run, attempts: Attempt[], existing: Set<string>): RunProgress {
  const queue = run.queue.filter((id) => existing.has(id));
  const inQueue = new Set(queue);
  const mine = chronological(
    attempts.filter((a) => a.runId === run.id && inQueue.has(a.puzzleId)),
  );

  const finished = new Set<string>();
  const solved = new Set<string>();
  const failed = new Set<string>();
  let retries: Retry[] = [];
  let completed = 0;

  for (const attempt of mine) {
    const id = attempt.puzzleId;
    if (finished.has(id)) continue;
    const retrying = retries.some((r) => r.puzzleId === id);
    retries = retries.filter((r) => r.puzzleId !== id);

    if (attempt.result === 'skipped') {
      finished.add(id);
      continue;
    }

    completed++;
    if (attempt.result === 'solved') {
      solved.add(id);
      finished.add(id);
    } else {
      failed.add(id);
      if (!retrying && retries.length < MAX_RETRIES) {
        retries.push({ puzzleId: id, readyAt: completed + RETRY_GAP });
      } else {
        finished.add(id);
      }
    }
  }

  const waiting = new Set(retries.map((r) => r.puzzleId));
  const fresh = queue.filter((id) => !finished.has(id) && !waiting.has(id));
  const due = retries.find((r) => r.readyAt <= completed);
  const current = due?.puzzleId ?? fresh[0] ?? retries[0]?.puzzleId ?? null;

  return {
    queue,
    current,
    remaining: fresh.length + retries.length,
    played: mine.length,
    solved: solved.size,
    failed: failed.size,
    progress: queue.length ? Math.min(1, solved.size / queue.length) : 1,
  };
}
