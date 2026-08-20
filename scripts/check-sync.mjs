/**
 * Proves cross-device sync against the real backend.
 *
 * Two independent browser contexts stand in for two devices: separate cookie
 * jars, separate IndexedDB. Device A imports and syncs; device B signs into the
 * same account and must end up with the library it never imported. Anything
 * short of that — mocking the transport, reusing one context — would test the
 * plumbing while assuming the thing that actually matters.
 *
 * Requires VITE_NEON_BASE_URL for the local run. Creates a throwaway account;
 * pass --email to reuse one, or --url to run against the deployed site instead
 * of a dev server.
 *
 * Running it against production is not redundant. Better Auth rejects origins
 * that are not on its trusted-domain list, and localhost is trusted by default
 * — so a local pass says nothing about whether the deployed origin works. That
 * exact gap shipped once already.
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { createServer } from 'vite';

const SAMPLE = readFileSync(new URL('../samples/back-rank.json', import.meta.url), 'utf8');
const arg = (name) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=')[1] : null;
};
const EMAIL = arg('email') ?? `motif-e2e-${Date.now()}@example.com`;
const PASSWORD = arg('password') ?? 'motif-test-passphrase-9271';

const failures = [];
const check = (label, ok) => {
  console.log(`${ok ? '  ok  ' : 'FAIL  '}${label}`);
  if (!ok) failures.push(label);
};

const target = arg('url');
const server = target ? null : await createServer({ server: { port: 5194 } });
if (server) await server.listen();
const url = target ?? 'http://localhost:5194';
console.log(`target: ${url}`);
const browser = await chromium.launch();

async function device(name) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.log(`  [${name}] page error: ${e.message}`));
  await page.goto(url);
  await page.waitForTimeout(400);
  return { context, page };
}

async function auth(page, mode) {
  await page.getByRole('button', { name: /Sign in to sync|Account/ }).click();
  await page.waitForTimeout(300);
  await page.locator('input[type="email"]').fill(EMAIL);
  await page.locator('input[type="password"]').fill(PASSWORD);
  await page.getByRole('button', { name: mode === 'up' ? 'Create an account' : 'Sign in' }).click();
  await page.waitForTimeout(2500);
}

try {
  console.log(`account: ${EMAIL}`);

  // ---- Device A: import, sign up, sync ----
  const a = await device('A');
  await a.page.getByRole('button', { name: 'Import puzzles' }).click();
  await a.page.locator('textarea').fill(SAMPLE);
  await a.page.waitForTimeout(300);
  await a.page.getByRole('button', { name: /Add 3 puzzles/ }).click();
  await a.page.waitForTimeout(400);
  check('device A imported the collection',
    await a.page.getByText('Back-rank mates').isVisible());

  await auth(a.page, 'up');
  const signedIn = await a.page.getByText(new RegExp(EMAIL.replace(/[.@+]/g, '\\$&'))).isVisible().catch(() => false);
  check('device A signed up', signedIn);
  if (!signedIn) {
    console.log('  account screen said:', (await a.page.locator('.bad, .notice').allTextContents()).join(' | '));
  }

  await a.page.getByRole('button', { name: 'Sync now' }).click();
  await a.page.waitForTimeout(4000);
  const statusA = (await a.page.locator('.screen p.muted').first().textContent()) ?? '';
  check(`device A synced (${statusA.trim()})`, /Last synced/.test(statusA));

  // ---- Device B: fresh browser, same account ----
  const b = await device('B');
  check('device B starts empty',
    await b.page.getByText('Nothing here yet').isVisible().catch(() => false));

  await auth(b.page, 'in');
  await b.page.waitForTimeout(5000);
  await b.page.getByRole('button', { name: '← Back' }).click();
  await b.page.waitForTimeout(1500);

  const arrived = await b.page.getByText('Back-rank mates').isVisible().catch(() => false);
  check('device B received the library it never imported', arrived);
  if (!arrived) {
    console.log('  device B home:', ((await b.page.locator('.screen').textContent()) ?? '').replace(/\s+/g, ' ').slice(0, 200));
  }
  await b.page.screenshot({ path: '/tmp/motif-sync-b.png' });

  // ---- Device C: a different account must see nothing ----
  // The privacy claim is RLS's alone, so it gets tested rather than trusted.
  const OTHER = `motif-e2e-other-${Date.now()}@example.com`;
  const c = await device('C');
  await c.page.getByRole('button', { name: /Sign in to sync|Account/ }).click();
  await c.page.waitForTimeout(300);
  await c.page.locator('input[type="email"]').fill(OTHER);
  await c.page.locator('input[type="password"]').fill(PASSWORD);
  await c.page.getByRole('button', { name: 'Create an account' }).click();
  await c.page.waitForTimeout(4000);
  await c.page.getByRole('button', { name: '← Back' }).click();
  await c.page.waitForTimeout(2000);
  const leaked = await c.page.getByText('Back-rank mates').isVisible().catch(() => false);
  check("a different account cannot see the first account's library", !leaked);

} catch (error) {
  console.log(`FAIL  threw: ${error.message}`);
  failures.push('exception');
} finally {
  await browser.close();
  await server?.close();
}

console.log(failures.length ? `\n${failures.length} failed` : '\nsync works end to end');
process.exit(failures.length ? 1 : 0);
