import { describe, expect, it } from 'vitest';
import type { Attempt, AttemptResult, Run } from '../data/backend';
import { puzzleRecords, recentIds, reviewIds, runProgress, statsFor, statusOf } from './derive';
import { MAX_RETRIES, RECENT_MEMORY, RETRY_GAP } from './session';

let clock = 0;

function attempt(puzzleId: string, result: AttemptResult, extra: Partial<Attempt> = {}): Attempt {
  return {
    id: `a${++clock}`,
    puzzleId,
    runId: null,
    result,
    mistakes: result === 'failed' ? 1 : 0,
    hinted: false,
    playedAt: clock,
    ...extra,
  };
}

const ids = (n: number) => Array.from({ length: n }, (_, i) => `p${i}`);

function makeRun(queue: string[]): Run {
  return { id: 'run', scope: 'c', mode: 'ordered', queue, startedAt: 0 };
}

/** Plays a run to the end: `answer` decides each result, as the solver would. */
function play(run: Run, answer: (id: string, served: number) => AttemptResult) {
  const attempts: Attempt[] = [];
  const existing = new Set(run.queue);
  const served: string[] = [];
  for (let progress = runProgress(run, attempts, existing); progress.current; ) {
    served.push(progress.current);
    attempts.push(attempt(progress.current, answer(progress.current, served.length), { runId: run.id }));
    progress = runProgress(run, attempts, existing);
  }
  return { served, attempts, progress: runProgress(run, attempts, existing) };
}

describe('puzzle records', () => {
  it('follows the latest result that was not a skip', () => {
    const records = puzzleRecords([
      attempt('a', 'failed'),
      attempt('a', 'solved'),
      attempt('a', 'skipped'),
      attempt('b', 'solved'),
      attempt('b', 'failed', { mistakes: 3 }),
      attempt('c', 'skipped'),
    ]);
    expect(statusOf(records, 'a')).toBe('solved');
    expect(statusOf(records, 'b')).toBe('failed');
    expect(statusOf(records, 'c')).toBe('unseen');
    expect(statusOf(records, 'd')).toBe('unseen');
    expect(records.get('a')).toMatchObject({ attempts: 2, mistakes: 1 });
    expect(records.get('b')).toMatchObject({ attempts: 2, mistakes: 3 });
  });

  it('reads attempts in the order they were played, not received', () => {
    const late = attempt('a', 'failed');
    const early = attempt('a', 'solved', { playedAt: late.playedAt - 1 });
    expect(statusOf(puzzleRecords([late, early]), 'a')).toBe('failed');
  });

  it('collects the review set and stats', () => {
    const records = puzzleRecords([attempt('p1', 'failed'), attempt('p2', 'solved'), attempt('p3', 'failed')]);
    expect(reviewIds(ids(4), records)).toEqual(['p1', 'p3']);
    expect(statsFor(ids(4), records)).toEqual({ total: 4, solved: 1, failed: 2, unseen: 1 });
  });

  it('lists recently played puzzles, newest first, skips included', () => {
    const attempts = [attempt('a', 'solved'), attempt('b', 'skipped'), attempt('a', 'failed')];
    expect(recentIds(attempts)).toEqual(['a', 'b']);
    const many = ids(RECENT_MEMORY + 5).map((id) => attempt(id, 'solved'));
    expect(recentIds(many)).toHaveLength(RECENT_MEMORY);
    expect(recentIds(many)[0]).toBe(`p${RECENT_MEMORY + 4}`);
  });
});

describe('run progress', () => {
  it('serves the queue in order and finishes', () => {
    const run = makeRun(ids(3));
    expect(runProgress(run, [], new Set(run.queue))).toMatchObject({
      current: 'p0',
      remaining: 3,
      progress: 0,
    });
    const { served, progress } = play(run, () => 'solved');
    expect(served).toEqual(ids(3));
    expect(progress).toMatchObject({ current: null, remaining: 0, solved: 3, progress: 1 });
  });

  it('brings a miss back once, after the gap', () => {
    const run = makeRun(ids(6));
    const { served, progress } = play(run, (id) => (id === 'p0' ? 'failed' : 'solved'));
    expect(served).toEqual(['p0', ...ids(6).slice(1, 1 + RETRY_GAP), 'p0', 'p4', 'p5']);
    expect(progress).toMatchObject({ solved: 5, failed: 1, current: null });
  });

  it('does not bring a retry back a second time', () => {
    const run = makeRun(ids(5));
    const { served } = play(run, (id) => (id === 'p0' ? 'failed' : 'solved'));
    expect(served.filter((id) => id === 'p0')).toHaveLength(2);
  });

  it('serves waiting retries early once the queue runs out', () => {
    const run = makeRun(ids(2));
    const { served } = play(run, (_, n) => (n <= 2 ? 'failed' : 'solved'));
    expect(served).toEqual(['p0', 'p1', 'p0', 'p1']);
  });

  it('caps the retries waiting', () => {
    // Missed one after another, as a second device might, with no retry served
    // in between: only the first MAX_RETRIES of them are owed another look.
    const run = makeRun(ids(MAX_RETRIES + 2));
    const attempts = run.queue.map((id) => attempt(id, 'failed', { runId: run.id }));
    const progress = runProgress(run, attempts, new Set(run.queue));
    expect(progress).toMatchObject({ remaining: MAX_RETRIES, current: 'p0', failed: MAX_RETRIES + 2 });
  });

  it('finishes a skipped puzzle without counting it', () => {
    const run = makeRun(ids(2));
    const { served, progress } = play(run, (id) => (id === 'p0' ? 'skipped' : 'solved'));
    expect(served).toEqual(['p0', 'p1']);
    expect(progress).toMatchObject({ solved: 1, failed: 0, progress: 0.5, played: 2 });
  });

  it('a skipped retry does not come back', () => {
    const run = makeRun(ids(5));
    const { served } = play(run, (id, n) => (id === 'p0' ? (n === 1 ? 'failed' : 'skipped') : 'solved'));
    expect(served.filter((id) => id === 'p0')).toHaveLength(2);
  });

  it('drops puzzles deleted since the run started', () => {
    const run = makeRun(ids(3));
    const progress = runProgress(run, [], new Set(['p0', 'p2']));
    expect(progress).toMatchObject({ queue: ['p0', 'p2'], remaining: 2 });
  });

  it('ignores attempts made outside the run', () => {
    const run = makeRun(ids(2));
    const progress = runProgress(run, [attempt('p0', 'solved')], new Set(run.queue));
    expect(progress.current).toBe('p0');
  });

  it('counts puzzles played on two devices at once', () => {
    const run = makeRun(ids(3));
    // Both devices served p0; one then played p1 as well.
    const attempts = [
      attempt('p0', 'solved', { runId: 'run' }),
      attempt('p0', 'failed', { runId: 'run' }),
      attempt('p1', 'solved', { runId: 'run' }),
    ];
    expect(runProgress(run, attempts, new Set(run.queue))).toMatchObject({
      current: 'p2',
      solved: 2,
      failed: 0,
    });
  });
});
