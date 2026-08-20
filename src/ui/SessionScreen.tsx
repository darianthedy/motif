import { useMemo, useState } from 'react';
import type { Puzzle } from '../model/puzzle';
import type { PuzzleResult } from '../model/runner';
import { completeCurrent, isFinished, progress, remainingCount, startSession } from '../model/session';
import type { SessionMode, SessionState } from '../model/session';
import { PuzzleView } from './PuzzleView';

interface Props {
  puzzles: Puzzle[];
  mode: SessionMode;
  collectionId: string | null;
  onExit: () => void;
}

export function SessionScreen({ puzzles, mode, collectionId, onExit }: Props) {
  const byId = useMemo(() => new Map(puzzles.map((p) => [p.id, p])), [puzzles]);
  const [session, setSession] = useState<SessionState>(() =>
    startSession(mode, collectionId, puzzles.map((p) => p.id)),
  );

  const current = session.current ? byId.get(session.current) : undefined;

  const handleComplete = (result: PuzzleResult) => {
    setSession((state) => completeCurrent(state, result));
  };

  if (isFinished(session) || !current) {
    return (
      <div className="session-done">
        <h2>Session complete</h2>
        <p className="muted">
          {session.solvedIds.length} of {session.queue.length} solved cleanly
          {session.failedIds.length > 0 && `, ${session.failedIds.length} missed`}.
        </p>
        <button type="button" onClick={onExit}>
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
      </header>

      {/* Keyed by puzzle id *and* completion count, so re-serving a retry
          remounts the view and starts it fresh rather than reusing the runner
          from the first attempt. */}
      <PuzzleView
        key={`${current.id}:${session.completed}`}
        puzzle={current}
        onComplete={handleComplete}
      />
    </div>
  );
}
