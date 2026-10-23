/** Said next to whatever an edit would need the server for. */
export function OfflineNote({ online }: { online: boolean }) {
  if (online) return null;
  return <p className="muted small">You're offline. Editing needs a connection; solving doesn't.</p>;
}
