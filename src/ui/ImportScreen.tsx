import { useRef, useState } from 'react';
import { importJson } from '../model/import/json';
import type { ImportResult } from '../model/import/json';
import { importLichessCsv } from '../model/import/lichess';
import { applyImport } from '../model/state';
import type { AppState } from '../model/state';

interface Props {
  state: AppState;
  onApply: (next: AppState, added: number, refreshed: number) => void;
  onExit: () => void;
}

/**
 * Distinguishes the two formats by shape rather than by asking.
 *
 * A JSON file starts with a brace once whitespace is stripped; the Lichess dump
 * is CSV. Getting this wrong is recoverable — the importer reports rejections
 * rather than throwing — but guessing correctly means one paste box instead of
 * a format dropdown nobody wants to think about.
 */
function detectAndParse(text: string): { result: ImportResult; format: string } {
  const trimmed = text.trim();

  // A URL that returns a web page — a share page, a login wall, a 404 handler,
  // an SPA fallback — is the most likely way this goes wrong, and it arrives
  // with a 200 status. Without this it would be parsed as CSV and reported as
  // "0 puzzles read", which says nothing about what actually happened.
  if (trimmed.startsWith('<')) {
    return {
      format: 'HTML',
      result: {
        groups: [],
        inserted: [],
        updated: [],
        rejected: [
          {
            index: -1,
            reason:
              'That is a web page, not a puzzle file. If it came from a URL, use the raw or direct-download link.',
          },
        ],
      },
    };
  }

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return { result: importJson(trimmed), format: 'JSON' };
  }
  return { result: importLichessCsv(trimmed), format: 'Lichess CSV' };
}

export function ImportScreen({ state, onApply, onExit }: Props) {
  const [text, setText] = useState('');
  const [name, setName] = useState('');
  const [preview, setPreview] = useState<{ result: ImportResult; format: string } | null>(null);
  const [url, setUrl] = useState('');
  const [fetching, setFetching] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const parse = (raw: string) => {
    setText(raw);
    if (!raw.trim()) {
      setPreview(null);
      return;
    }
    const parsed = detectAndParse(raw);
    setPreview(parsed);
    if (!name && parsed.result.collectionName) setName(parsed.result.collectionName);
  };

  const onFile = async (file: File | undefined) => {
    if (!file) return;
    parse(await file.text());
  };

  /**
   * Fetches a collection from a URL.
   *
   * Exists because typing or pasting a quarter of a megabyte of JSON into a
   * phone is not a workflow. The host must send CORS headers — raw.github,
   * gists and most static hosts do; a Drive or Dropbox *share page* does not,
   * so those need their direct-download form.
   */
  const fetchUrl = async () => {
    const target = url.trim();
    if (!target) return;
    setFetching(true);
    setFetchError(null);
    try {
      const response = await fetch(target);
      if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
      parse(await response.text());
    } catch (error) {
      setFetchError(
        `${(error as Error).message}. If the host does not allow cross-origin reads, ` +
          'download the file and use "Choose a file" instead.',
      );
    } finally {
      setFetching(false);
    }
  };

  const result = preview?.result;
  const incoming = result ? result.inserted.length + result.updated.length : 0;
  // A file carrying its own chapter names does not need one from us, and
  // asking would only invite collapsing eighteen chapters into one bucket.
  const namedGroups = result?.groups.filter((group) => group.name) ?? [];
  const multiCollection = namedGroups.length > 1;

  const apply = () => {
    if (!result) return;
    const collectionName = multiCollection
      ? undefined
      : name.trim() || result.collectionName || 'Imported';
    const { state: next, added, refreshed } = applyImport(state, result, collectionName);
    onApply(next, added, refreshed);
  };

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" onClick={onExit}>
          ← Back
        </button>
        <h2>Import puzzles</h2>
      </header>

      <p className="muted small">
        Paste a JSON collection or rows from the Lichess puzzle dump. The format is
        detected automatically.
      </p>

      <input
        ref={fileInput}
        type="file"
        accept=".json,.csv,text/plain"
        style={{ display: 'none' }}
        onChange={(event) => void onFile(event.target.files?.[0])}
      />
      <button type="button" onClick={() => fileInput.current?.click()}>
        Choose a file
      </button>

      <div className="url-row">
        <input
          value={url}
          onChange={(event) => setUrl(event.target.value)}
          placeholder="…or paste a URL"
          inputMode="url"
          autoCapitalize="off"
          autoCorrect="off"
          spellCheck={false}
        />
        <button type="button" onClick={() => void fetchUrl()} disabled={!url.trim() || fetching}>
          {fetching ? 'Fetching…' : 'Fetch'}
        </button>
      </div>
      {fetchError && <p className="bad small">{fetchError}</p>}

      <textarea
        value={text}
        onChange={(event) => parse(event.target.value)}
        placeholder={'{ "collection": "Back-rank mates", "puzzles": [ … ] }'}
        rows={8}
        spellCheck={false}
      />

      {result && (
        <div className="import-preview">
          <p>
            <strong>{preview.format}</strong> — {incoming} puzzle{incoming === 1 ? '' : 's'} read
            {result.rejected.length > 0 && (
              <span className="bad"> · {result.rejected.length} rejected</span>
            )}
          </p>

          {result.rejected.length > 0 && (
            /* Shown rather than swallowed: a silently dropped row is how a
               collection quietly ends up incomplete. */
            <ul className="rejects">
              {result.rejected.slice(0, 5).map((reject) => (
                <li key={`${reject.index}-${reject.reason}`} className="muted small">
                  {/* A negative index means the problem is with the file as a
                      whole, not a row in it. "row 0" would be a lie. */}
                  {reject.index >= 0 && <>row {reject.index + 1}: </>}
                  {reject.reason}
                </li>
              ))}
              {result.rejected.length > 5 && (
                <li className="muted small">…and {result.rejected.length - 5} more</li>
              )}
            </ul>
          )}

          {multiCollection ? (
            <div className="field">
              <span className="muted small">
                {namedGroups.length} collections in this file
              </span>
              <ul className="groups">
                {namedGroups.map((group) => (
                  <li key={group.name} className="small">
                    {group.name}{' '}
                    <span className="muted">
                      · {group.puzzles.length} puzzle{group.puzzles.length === 1 ? '' : 's'}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <label className="field">
              <span className="muted small">Collection name</span>
              <input
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Imported"
              />
            </label>
          )}

          <button type="button" onClick={apply} disabled={incoming === 0}>
            Add {incoming} puzzle{incoming === 1 ? '' : 's'}
          </button>
        </div>
      )}
    </div>
  );
}
