import { useRef, useState } from 'react';
import { importJson } from '../model/import/json';
import type { ImportResult } from '../model/import/json';
import type { Collection } from '../model/puzzle';
import { OfflineNote } from './OfflineNote';

/** Where a single-collection file goes: into a collection, or a new one by name. */
export type ImportTarget = { collectionId: string } | { name: string };

interface Props {
  collections: Collection[];
  online: boolean;
  /** `target` is unset for a file of several collections, which each become new ones. */
  onApply: (result: ImportResult, target?: ImportTarget) => void;
  onExit: () => void;
}

const NEW = '';

export function ImportScreen({ collections, online, onApply, onExit }: Props) {
  const [text, setText] = useState('');
  const [name, setName] = useState('');
  // A collection id, or NEW for a new collection called `name`.
  const [into, setInto] = useState(NEW);
  const [result, setResult] = useState<ImportResult | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const parse = (raw: string) => {
    setText(raw);
    if (!raw.trim()) {
      setResult(null);
      return;
    }
    const parsed = importJson(raw.trim());
    setResult(parsed);
    if (!name && parsed.collectionName) setName(parsed.collectionName);
  };

  const onFile = async (file: File | undefined) => {
    if (!file) return;
    parse(await file.text());
  };

  const incoming = result?.groups.reduce((sum, group) => sum + group.puzzles.length, 0) ?? 0;
  // A file of several collections makes one new collection of each, named by
  // the file: asking for one target would only invite collapsing eighteen
  // chapters into one bucket.
  const groups = result?.groups ?? [];
  const multiCollection = groups.length > 1;

  const apply = () => {
    if (!result) return;
    if (multiCollection) onApply(result);
    else if (into !== NEW) onApply(result, { collectionId: into });
    else onApply(result, { name: name.trim() || result.collectionName || 'Imported' });
  };

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" aria-label="Back" onClick={onExit}>
          ←
        </button>
        <h2>Import puzzles</h2>
      </header>

      <p className="muted small">Choose a JSON collection file, or paste one.</p>

      <input
        ref={fileInput}
        type="file"
        accept=".json,application/json"
        style={{ display: 'none' }}
        onChange={(event) => void onFile(event.target.files?.[0])}
      />
      <button type="button" onClick={() => fileInput.current?.click()}>
        Choose a file
      </button>

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
            {incoming} puzzle{incoming === 1 ? '' : 's'} read
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
                {groups.length} new collections from this file
              </span>
              <ul className="groups">
                {groups.map((group, index) => (
                  <li key={index} className="small">
                    {group.name ?? 'Imported'}{' '}
                    <span className="muted">
                      · {group.puzzles.length} puzzle{group.puzzles.length === 1 ? '' : 's'}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <>
              <label className="field">
                <span className="muted small">Add to</span>
                <select value={into} onChange={(event) => setInto(event.target.value)}>
                  <option value={NEW}>A new collection</option>
                  {collections.map((collection) => (
                    <option key={collection.id} value={collection.id}>
                      {collection.name}
                    </option>
                  ))}
                </select>
              </label>
              {into === NEW && (
                <label className="field">
                  <span className="muted small">Collection name</span>
                  <input
                    value={name}
                    onChange={(event) => setName(event.target.value)}
                    placeholder="Imported"
                  />
                </label>
              )}
            </>
          )}

          <button type="button" onClick={apply} disabled={incoming === 0 || !online}>
            Add {incoming} puzzle{incoming === 1 ? '' : 's'}
          </button>
          <OfflineNote online={online} />
        </div>
      )}
    </div>
  );
}
