import { useState } from 'react';
import { useLibrary } from '../useLibrary';
import { AccountScreen } from './AccountScreen';
import { NavMenu } from './NavMenu';
import type { Section } from './NavMenu';
import { PuzzlesSection } from './PuzzlesSection';
import type { PuzzlesRoute } from './PuzzlesSection';
import { SignInScreen } from './SignInScreen';
import './App.css';

export function App() {
  const {
    user,
    library,
    loaded,
    online,
    status,
    pending,
    write,
    startRun,
    recordAttempt,
    signIn,
    signOut,
  } = useLibrary();
  const [section, setSection] = useState<Section>('puzzles');
  const [puzzlesRoute, setPuzzlesRoute] = useState<PuzzlesRoute>({ name: 'home' });
  const [notice, setNotice] = useState<string | null>(null);

  // Still finding out who is signed in.
  if (user === undefined) return <main className="app" />;

  if (user === null) {
    return (
      <main className="app">
        <SignInScreen online={online} onSubmit={signIn} />
      </main>
    );
  }

  // The cached copy is read asynchronously; rendering an empty library first
  // would flash "nothing here yet" over an existing collection on every launch.
  if (!library) {
    return (
      <main className="app">
        {loaded && (
          <div className="screen">
            <h1>Motif</h1>
            <p className="muted">
              {online
                ? status.kind === 'error'
                  ? `Could not load your library: ${status.message}`
                  : 'Loading your library…'
                : "You're offline, and this device has no copy of your library yet. " +
                  'Connect once to download it.'}
            </p>
          </div>
        )}
      </main>
    );
  }

  /** Runs an online edit, reporting a failure rather than dropping it. */
  const edit = async (fn: Parameters<typeof write>[0], done?: string) => {
    try {
      await write(fn);
      if (done) setNotice(done);
      return true;
    } catch (error) {
      setNotice(`That didn't save: ${(error as Error).message}`);
      return false;
    }
  };

  // The menu, the sync state and notices belong to a section's front page;
  // deeper screens keep the whole screen to themselves.
  const atFront = section === 'account' || puzzlesRoute.name === 'home';

  return (
    <main className={atFront ? 'app with-nav' : 'app'}>
      {atFront && (
        <>
          {!online && (
            <p className="offline small">
              Offline{pending > 0 && ` · ${pending} to upload`}
            </p>
          )}
          {online && status.kind === 'error' && (
            <p className="bad small">Couldn't reach the server: {status.message}</p>
          )}
          {notice && (
            <p className="notice" onClick={() => setNotice(null)}>
              {notice}
            </p>
          )}
        </>
      )}

      {section === 'puzzles' && (
        <PuzzlesSection
          library={library}
          online={online}
          route={puzzlesRoute}
          onNavigate={setPuzzlesRoute}
          edit={edit}
          startRun={startRun}
          recordAttempt={recordAttempt}
        />
      )}
      {section === 'account' && (
        <AccountScreen
          user={user}
          online={online}
          status={status}
          pending={pending}
          onSignOut={() => {
            // Whoever signs in next starts on the front page, not here.
            setSection('puzzles');
            setPuzzlesRoute({ name: 'home' });
            void signOut();
          }}
        />
      )}

      {atFront && (
        <NavMenu
          section={section}
          onSelect={(next) => {
            setNotice(null);
            setSection(next);
          }}
        />
      )}
    </main>
  );
}
