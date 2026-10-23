import { useMemo } from 'react';
import type { AttemptResult } from '../data/backend';
import type { RunProgress } from '../model/derive';
import type { Puzzle } from '../model/puzzle';
import { PuzzleView } from './PuzzleView';

interface Props {
  progress: RunProgress;
  puzzles: Puzzle[];
  /** Records the current puzzle's result, which moves the run on. */
  onAttempt: (result: AttemptResult, mistakes: number, hinted: boolean) => void;
  /** The run reached its end. */
  onFinished: () => void;
  onExit: () => void;
}

export function SessionScreen({ progress, puzzles, onAttempt, onFinished, onExit }: Props) {
  const current = useMemo(
    () => puzzles.find((puzzle) => puzzle.id === progress.current),
    [progress.current, puzzles],
  );

  // Always available: a position can be legal and still be wrong, and being
  // stuck with no way forward is worse than an occasional skip. Recorded, so the puzzle does not come back this
  // run, but as neither a solve nor a miss.
  const handleSkip = () => onAttempt('skipped', 0, false);

  if (!current) {
    return (
      <div className="session-done">
        <h2>Session complete</h2>
        <p className="muted">
          {progress.solved} of {progress.queue.length} solved cleanly
          {progress.failed > 0 && `, ${progress.failed} missed`}.
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
          <div className="progress-fill" style={{ width: `${progress.progress * 100}%` }} />
        </div>
        <span className="muted count">{progress.remaining}</span>
        <button type="button" className="link" onClick={handleSkip} title="Skip this puzzle">
          Skip
        </button>
      </header>

      {/* Keyed by puzzle id *and* attempts played, so a re-served retry
          remounts the view and starts a fresh runner rather than reusing the
          one from the first attempt. */}
      <PuzzleView
        key={`${current.id}:${progress.played}`}
        puzzle={current}
        onComplete={onAttempt}
      />
    </div>
  );
}
