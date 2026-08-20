import { useMemo } from 'react';
import { importJson } from '../model/import/json';
import sample from '../../samples/back-rank.json?raw';

/**
 * Placeholder shell. The model layer is built and tested; the board and the
 * session UI are the next piece of work. This renders the sample import so the
 * build, the PWA manifest and the deploy path can all be verified before any
 * of the real UI exists.
 */
export function App() {
  const result = useMemo(() => importJson(sample), []);

  return (
    <main style={{ padding: '2rem', maxWidth: '32rem', margin: '0 auto' }}>
      <h1 style={{ marginBottom: '0.25rem' }}>Chesslingo</h1>
      <p style={{ color: 'var(--muted)', marginTop: 0 }}>
        Model layer ready — {result.inserted.length} sample puzzles parsed from{' '}
        {result.collectionName ?? 'an unnamed collection'}.
      </p>
      <ul style={{ color: 'var(--muted)', lineHeight: 1.7 }}>
        {result.inserted.map((puzzle) => (
          <li key={puzzle.id}>
            {puzzle.solutions.length} solution{puzzle.solutions.length === 1 ? '' : 's'}
            {puzzle.rating ? ` · rated ${puzzle.rating}` : ''}
          </li>
        ))}
      </ul>
    </main>
  );
}
