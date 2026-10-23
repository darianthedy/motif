import { useState } from 'react';
import { usingDevAccount } from '../data/account';

interface Props {
  online: boolean;
  onSubmit: (mode: 'in' | 'up', email: string, password: string) => Promise<void>;
}

/**
 * The first screen until someone signs in. The library lives in the account,
 * so there is nothing to show without one.
 */
export function SignInScreen({ online, onSubmit }: Props) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (mode: 'in' | 'up') => {
    setBusy(true);
    setError(null);
    try {
      await onSubmit(mode, email.trim(), password);
    } catch (caught) {
      setError((caught as Error).message);
      setBusy(false);
    }
  };

  const ready = online && !busy && email && password;

  return (
    <div className="screen">
      <h1>Motif</h1>
      <p className="muted small">
        Sign in to see your puzzles. Your library is private to your account and the same on
        every device.
      </p>
      {usingDevAccount && (
        <p className="muted small">
          No database is configured, so any email and password will do, and the library stays in
          this browser.
        </p>
      )}

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
        <button type="button" disabled={!ready} onClick={() => void submit('in')}>
          {busy ? 'Working…' : 'Sign in'}
        </button>
        <button type="button" className="link" disabled={!ready} onClick={() => void submit('up')}>
          Create an account
        </button>
      </div>

      {!online && <p className="muted small">You're offline. Signing in needs a connection.</p>}
      {error && <p className="bad small">{error}</p>}
    </div>
  );
}
