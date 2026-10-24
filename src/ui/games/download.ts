/** Hands the viewer a file to save. */
export function downloadText(filename: string, text: string, type = 'application/x-chess-pgn') {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  // Revoked later rather than now: Safari reads the URL after click() returns.
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/** A name that every file system accepts. */
export function fileName(name: string, extension: string): string {
  const safe = name.replace(/[\\/:*?"<>|]+/g, '').replace(/\s+/g, ' ').trim();
  return `${safe || 'games'}.${extension}`;
}
