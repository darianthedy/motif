import { useMemo, useState } from 'react';
import { importJson } from '../model/import/json';
import type { SessionMode } from '../model/session';
import { SessionScreen } from './SessionScreen';
import './App.css';
import sample from '../../samples/back-rank.json?raw';

/**
 * Temporary shell: the sample collection, hard-wired, so the solve loop is
 * usable end to end. Collections, import and persistence come next; this exists
 * so the board and session can be played with on a real phone before then.
 */
export function App() {
  const puzzles = useMemo(() => importJson(sample).inserted, []);
  const [mode, setMode] = useState<SessionMode | null>(null);

  if (mode) {
    return (
      <main className="app">
        <SessionScreen
          puzzles={puzzles}
          mode={mode}
          collectionId="sample"
          onExit={() => setMode(null)}
        />
      </main>
    );
  }

  return (
    <main className="app">
      <h1>Motif</h1>
      <p className="muted">Back-rank mates · {puzzles.length} puzzles</p>
      <div className="menu">
        <button type="button" onClick={() => setMode('ordered')}>
          Solve in order
        </button>
        <button type="button" onClick={() => setMode('randomInCollection')}>
          Solve shuffled
        </button>
      </div>
    </main>
  );
}
