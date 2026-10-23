/**
 * Proves the app against the real database, from two devices.
 *
 * Two independent browser contexts stand in for two devices: separate cookie
 * jars, separate IndexedDB. Every edit is written straight to the database, so
 * what this checks is that each device sees the other's: an edit on A appears
 * on B, a delete on A disappears on B, and attempts made offline on A upload
 * once A reconnects. A third account must see none of it. That last check is
 * the privacy claim, and it is RLS's alone, so it is tested rather than
 * trusted.
 *
 * Requires db/0001_schema.sql to have been applied to the target database, and
 * VITE_NEON_BASE_URL for the local run. Creates throwaway accounts; pass
 * --email to reuse one, or --url to run against the deployed site instead of a
 * dev server.
 *
 * Running it against production is not redundant. Neon Auth rejects origins
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
  // Deletions ask for confirmation; a device in this script always means it.
  page.on('dialog', (dialog) => void dialog.accept());
  await page.goto(url);
  await page.waitForTimeout(800);
  return { context, page };
}

async function auth(page, email, mode) {
  await page.locator('input[type="email"]').fill(email);
  await page.locator('input[type="password"]').fill(PASSWORD);
  await page.getByRole('button', { name: mode === 'up' ? 'Create an account' : 'Sign in' }).click();
  await page.waitForTimeout(3000);
}

/** Reopens the app, which reads the library afresh from the database. */
async function reopen(page) {
  await page.reload();
  await page.waitForTimeout(3000);
}

const text = async (page) =>
  ((await page.locator('.screen').first().textContent().catch(() => '')) ?? '').replace(/\s+/g, ' ');

async function puzzleCount(page) {
  await page.getByText('Back-rank mates').click();
  await page.getByRole('button', { name: 'Browse puzzles' }).click();
  await page.waitForTimeout(300);
  const count = await page.locator('.puzzle-row').count();
  await page.getByRole('button', { name: /←/ }).first().click();
  await page.getByRole('button', { name: /←/ }).first().click();
  await page.waitForTimeout(300);
  return count;
}

try {
  console.log(`account: ${EMAIL}`);

  // ---- Device A: sign up, import ----
  const a = await device('A');
  await auth(a.page, EMAIL, 'up');
  const signedIn = await a.page.getByRole('button', { name: 'Import puzzles' }).isVisible().catch(() => false);
  check('device A signed up', signedIn);
  if (!signedIn) console.log('  sign-in screen said:', await text(a.page));

  await a.page.getByRole('button', { name: 'Import puzzles' }).click();
  await a.page.locator('textarea').fill(SAMPLE);
  await a.page.waitForTimeout(300);
  await a.page.getByRole('button', { name: /Add 3 puzzles/ }).click();
  await a.page.waitForTimeout(3000);
  check('device A imported the collection', await a.page.getByText('Back-rank mates').isVisible());

  // ---- Device B: same account, fresh browser ----
  const b = await device('B');
  await auth(b.page, EMAIL, 'in');
  const arrived = await b.page.getByText('Back-rank mates').isVisible().catch(() => false);
  check('device B sees the library it never imported', arrived);
  if (!arrived) console.log('  device B home:', (await text(b.page)).slice(0, 200));

  // ---- An edit on A appears on B ----
  await a.page.getByText('Back-rank mates').click();
  await a.page.getByRole('button', { name: 'Browse puzzles' }).click();
  await a.page.locator('.puzzle-row').first().click();
  await a.page.locator('textarea').fill('Edited on A');
  await a.page.getByRole('button', { name: 'Save comment' }).click();
  await a.page.waitForTimeout(2500);

  await reopen(b.page);
  await b.page.getByText('Back-rank mates').click();
  await b.page.getByRole('button', { name: 'Browse puzzles' }).click();
  await b.page.locator('.puzzle-row').first().click();
  await b.page.waitForSelector('.facts');
  check('a comment edited on device A appears on device B',
    (await b.page.locator('textarea').inputValue()) === 'Edited on A');

  // ---- A delete on A disappears on B ----
  await a.page.getByRole('button', { name: 'Delete puzzle' }).click();
  await a.page.waitForTimeout(2500);
  await reopen(b.page);
  check('a puzzle deleted on device A is gone from device B', (await puzzleCount(b.page)) === 2);

  // ---- Offline attempts on A upload once A reconnects ----
  await reopen(a.page);
  await a.context.setOffline(true);
  await a.page.waitForTimeout(300);
  await a.page.getByText('Back-rank mates').click();
  await a.page.getByRole('button', { name: 'Solve in order' }).click();
  await a.page.waitForSelector('[data-square="a1"]');
  await a.page.getByRole('button', { name: 'Skip' }).click();
  await a.page.waitForTimeout(300);
  await a.page.getByRole('button', { name: 'Stop' }).click();
  await a.page.waitForTimeout(300);
  check('device A queues play while offline',
    /to upload/.test((await a.page.locator('.offline').textContent().catch(() => '')) ?? ''));

  await reopen(b.page);
  check('device B does not see it yet',
    !(await b.page.locator('.pill').isVisible().catch(() => false)));

  await a.context.setOffline(false);
  await a.page.waitForTimeout(4000);
  await reopen(b.page);
  check('once device A reconnects, device B sees the run it started',
    await b.page.locator('.pill').isVisible().catch(() => false));

  // ---- Device C: a different account must see nothing ----
  const c = await device('C');
  await auth(c.page, `motif-e2e-other-${Date.now()}@example.com`, 'up');
  const leaked = await c.page.getByText('Back-rank mates').isVisible().catch(() => false);
  check("a different account cannot see the first account's library", !leaked);
} catch (error) {
  console.log(`FAIL  threw: ${error.message}`);
  failures.push('exception');
} finally {
  await browser.close();
  await server?.close();
}

console.log(failures.length ? `\n${failures.length} failed` : '\nthe database works end to end');
process.exit(failures.length ? 1 : 0);
