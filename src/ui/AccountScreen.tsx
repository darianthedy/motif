import { usingDevAccount } from '../data/account';
import type { User } from '../data/account';
import type { SyncStatus } from '../useLibrary';
import { OfflineNote } from './OfflineNote';

interface Props {
  user: User;
  online: boolean;
  status: SyncStatus;
  /** Runs and attempts waiting to upload. */
  pending: number;
  onSignOut: () => void;
}

function describeSync(online: boolean, status: SyncStatus, pending: number): string {
  const waiting = `${pending} ${pending === 1 ? 'result' : 'results'} waiting to upload`;
  if (!online) return pending ? `Offline · ${waiting}` : 'Offline';
  if (status.kind === 'syncing') return 'Syncing…';
  if (status.kind === 'error') return `Couldn't reach the server: ${status.message}`;
  return pending ? waiting : 'Up to date';
}

/** Who is signed in, and whether this device is caught up with the server. */
export function AccountScreen({ user, online, status, pending, onSignOut }: Props) {
  return (
    <div className="screen">
      <h1>Account</h1>

      <dl className="facts">
        <dt>Signed in as</dt>
        <dd>{user.email}</dd>
        <dt>Sync</dt>
        <dd className={online && status.kind === 'error' ? 'bad' : undefined}>
          {describeSync(online, status, pending)}
        </dd>
      </dl>
      {usingDevAccount && (
        <p className="muted small">
          No database is configured, so this library stays in this browser.
        </p>
      )}

      <div className="menu">
        <button type="button" onClick={onSignOut} disabled={!online}>
          Sign out
        </button>
        <OfflineNote online={online} />
      </div>
    </div>
  );
}
