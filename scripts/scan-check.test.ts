import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { readScan } from './scan-check';

/** The fixtures the iOS ScanImportTests run too: one behaviour, two languages. */
interface Case {
  name: string;
  file: unknown;
  accepted: { key: string; flagged: boolean }[];
  rejected: { index: number; reason: string }[];
}
const fixtures = JSON.parse(
  readFileSync(new URL('../iOS/Motif/MotifTests/Fixtures/scan/scan-import.json', import.meta.url), 'utf8'),
) as { version: number; cases: Case[] };

describe('scan checks', () => {
  it.each(fixtures.cases.map((c) => [c.name, c] as const))('%s', (_, c) => {
    const result = readScan(JSON.stringify(c.file));
    expect(result.rejected).toEqual(c.rejected);
    expect(result.puzzles.map(({ key, flagged }) => ({ key, flagged }))).toEqual(c.accepted);
  });

  it('reports a file that is not JSON', () => {
    expect(readScan('{').rejected[0].reason).toMatch(/^Not valid JSON: /);
  });
});
