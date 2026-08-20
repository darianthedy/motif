import { useMemo } from 'react';
import type { Puzzle } from '../model/puzzle';
import type { PuzzleResult } from '../model/runner';
import { completeCurrent, isFinished, progress, remainingCount, skipCurrent } from '../model/session';
import type { SessionState } from '../model/session';
import { PuzzleView } from './PuzzleView';

interface Props {
  session: SessionState;
  puzzles: Record<string, Puzzle>;
  /** Persist the advanced session. Called once per completed puzzle. */
  onSession: (session: SessionState) => void;
  onResult: (puzzleId: string, result: PuzzleResult, mistakes: number) => void;
  /** Session reached its end: clear it so the next start is fresh. */
  onFinished: () => void;
  onExit: () => void;
}

export function SessionScreen({
  session,
  puzzles,
  onSession,
  onResult,
  onFinished,
  onExit,
}: Props) {
  const current = session.current ? puzzles[session.current] : undefined;
  const solvedCount = session.solvedIds.length;

  const summary = useMemo(
    () => ({ solved: solvedCount, missed: session.failedIds.length, total: session.queue.length }),
    [session.failedIds.length, session.queue.length, solvedCount],
  );

  const handleComplete = (result: PuzzleResult, mistakes: number) => {
    if (!session.current) return;
    onResult(session.current, result, mistakes);
    onSession(completeCurrent(session, result));
  };

  // Always available, not only for puzzles detected as broken: a position can
  // be legal and still be wrong, and being stuck with no way forward is worse
  // than an occasional skip.
  const handleSkip = () => onSession(skipCurrent(session));

  if (isFinished(session) || !current) {
    return (
      <div className="session-done">
        <h2>Session complete</h2>
        <p className="muted">
          {summary.solved} of {summary.total} solved cleanly
          {summary.missed > 0 && `, ${summary.missed} missed`}.
        </p>
        <button type="button" onClick={onFinished}>
          Done
        </button>
      </div>
    );
  }

  return (
    <div className="session">
      <header className="session-bar">
        <button type="button" className="link" onClick={onExit}>
          Stop
        </button>
        <div className="progress" aria-label="Session progress">
          <div className="progress-fill" style={{ width: `${progress(session) * 100}%` }} />
        </div>
        <span className="muted count">{remainingCount(session)}</span>
        <button type="button" className="link" onClick={handleSkip} title="Skip this puzzle">
          Skip
        </button>
      </header>

      {/* Keyed by puzzle id *and* completion count, so a re-served retry
          remounts the view and starts a fresh runner rather than reusing the
          one from the first attempt. */}
      <PuzzleView
        key={`${current.id}:${session.completed}`}
        puzzle={current}
        onComplete={handleComplete}
        onSkip={handleSkip}
      />
    </div>
  );
}
