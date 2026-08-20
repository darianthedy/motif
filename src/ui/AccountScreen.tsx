import { useState } from 'react';
import { signInWithPassword, signOut, signUp, syncAvailable } from '../model/neon';
import type { SyncUser } from '../model/neon';
import type { SyncStatus } from '../useSync';

interface Props {
  user: SyncUser | null;
  status: SyncStatus;
  onSyncNow: () => void;
  onAuthChanged: () => void;
  onExit: () => void;
}

function describe(status: SyncStatus): string {
  switch (status.kind) {
    case 'off':
      return 'Sync is not configured for this build.';
    case 'signedOut':
      return 'Signed out — this device keeps its own library.';
    case 'syncing':
      return 'Syncing…';
    case 'error':
      return `Sync failed: ${status.message}`;
    case 'idle':
      return status.at ? `Last synced ${new Date(status.at).toLocaleTimeString()}` : 'Ready.';
  }
}

export function AccountScreen({ user, status, onSyncNow, onAuthChanged, onExit }: Props) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const submit = async (mode: 'in' | 'up') => {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      if (mode === 'up') {
        await signUp(email.trim(), password);
        // Depending on the project's settings this either signs in directly or
        // waits on a confirmation email, so say so rather than appearing stuck.
        setNotice('Account created. If confirmation is required, check your email.');
      } else {
        await signInWithPassword(email.trim(), password);
      }
      setPassword('');
      onAuthChanged();
    } catch (caught) {
      setError((caught as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" onClick={onExit}>
          ← Back
        </button>
        <h2>Account</h2>
      </header>

      <p className="muted small">{describe(status)}</p>

      {!syncAvailable && (
        <p className="muted small">
          Set VITE_NEON_BASE_URL at build time to enable it.
        </p>
      )}

      {syncAvailable && !user && (
        <>
          <p className="muted small">
            Signing in keeps your puzzles and progress on every device. Your library is
            private to your account.
          </p>
          <label className="field">
            <span className="muted small">Email</span>
            <input
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              type="email"
              inputMode="email"
              autoCapitalize="off"
              autoCorrect="off"
              autoComplete="email"
            />
          </label>
          <label className="field">
            <span className="muted small">Password</span>
            <input
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              type="password"
              autoComplete="current-password"
            />
          </label>
          <div className="menu">
            <button type="button" disabled={busy || !email || !password} onClick={() => void submit('in')}>
              {busy ? 'Working…' : 'Sign in'}
            </button>
            <button
              type="button"
              className="link"
              disabled={busy || !email || !password}
              onClick={() => void submit('up')}
            >
              Create an account
            </button>
          </div>
        </>
      )}

      {syncAvailable && user && (
        <>
          <p className="small">Signed in as {user.email}</p>
          {/* The local library is never cleared on sign-out: it is the source
              of truth for the running session, and wiping it would turn a
              mis-tap into data loss. */}
          <div className="menu">
            <button type="button" onClick={onSyncNow} disabled={status.kind === 'syncing'}>
              Sync now
            </button>
            <button type="button" className="link" onClick={() => void signOut().then(onAuthChanged)}>
              Sign out
            </button>
          </div>
        </>
      )}

      {error && <p className="bad small">{error}</p>}
      {notice && <p className="notice">{notice}</p>}
    </div>
  );
}
