/// <reference types="node" />
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { expect, it } from 'vitest';
import { fixtureDirectory, generateFixtures } from '../../scripts/export-ios-fixtures';

it('keeps the committed iOS parity fixtures synchronized with the TypeScript spec', () => {
  for (const [name, generated] of Object.entries(generateFixtures())) {
    expect(readFileSync(resolve(fixtureDirectory, name), 'utf8'),
      `${name} is stale; run npm run export:ios-fixtures`).toBe(generated);
  }
});
