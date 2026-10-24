/**
 * Drives the Games section in a real browser: make a collection, paste PGN,
 * step through a game, play a variation in, comment, flip, edit details,
 * export, move, reorder, and open offline.
 *
 * Runs against the in-memory backend, like e2e-solve.mjs, so it needs no
 * database and leaves nothing behind.
 *
 * Usage: node scripts/e2e-games.mjs [--headed] [--shots=<dir>]
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { createServer } from 'vite';

const HEADED = process.argv.includes('--headed');
const SHOTS = process.argv.find((arg) => arg.startsWith('--shots'))?.split('=')[1] ?? (process.argv.includes('--shots') ? '/tmp' : null);

const PGN = `[Event "Hoogovens"]
[Site "Wijk aan Zee"]
[Date "1999.01.20"]
[Round "4"]
[White "Kasparov"]
[Black "Topalov"]
[Result "1-0"]

1. e4 d6 2. d4 Nf6 3. Nc3 g6 (3... e5 {the other way}) 4. Be3 Bg7 1-0

[White "Bad"]
[Black "Game"]

1. e4 e4 *

[White "Me"]
[Black "Club friend"]
[Result "*"]

1. d4 d5 2. c4 *
`;

const failures = [];
function check(label, condition) {
  if (condition) {
    console.log(`  ok  ${label}`);
  } else {
    console.log(`FAIL  ${label}`);
    failures.push(label);
  }
}

async function squareCentre(page, square) {
  const box = await page.locator(`[data-square="${square}"]`).boundingBox();
  if (!box) throw new Error(`no such square: ${square}`);
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

async function tap(page, square) {
  const { x, y } = await squareCentre(page, square);
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.up();
  await page.waitForTimeout(60);
}

const text = async (locator) => ((await locator.textContent()) ?? '').replace(/\s+/g, ' ').trim();
const shot = async (page, name) => {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/motif-games-${name}.png`, fullPage: true });
};
const settle = (page) => page.waitForTimeout(400);

process.env.VITE_NEON_BASE_URL = '';
const server = await createServer({ server: { port: 5198 } });
await server.listen();
const url = 'http://localhost:5198';

const browser = await chromium.launch({ headless: !HEADED });
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, acceptDownloads: true });
const page = await context.newPage();

try {
  await page.goto(url);
  await page.locator('input[type="email"]').fill('games@example.com');
  await page.locator('input[type="password"]').fill('anything');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await settle(page);

  // ---- The section ----
  await page.getByRole('navigation').getByRole('button', { name: 'Games' }).click();
  check('the menu has a Games section', await page.getByRole('heading', { name: 'Games' }).isVisible());
  check('Puzzles, Games, Account, in that order',
    (await page.getByRole('navigation').getByRole('button').allTextContents()).join(',') === 'Puzzles,Games,Account');

  page.once('dialog', (d) => d.accept('Openings'));
  await page.getByRole('button', { name: 'New collection' }).click();
  await settle(page);
  check('a new collection opens', await page.getByRole('heading', { name: 'Openings' }).isVisible());

  // ---- Adding ----
  await page.getByRole('button', { name: 'Add games' }).click();
  await page.locator('textarea').fill(PGN);
  const preview = await text(page.locator('.import-preview'));
  check(`a pasted file reads its games and reports the bad one (${preview.slice(0, 50)})`,
    preview.includes('2 games read') && preview.includes('1 couldn\'t be read') && preview.includes('game 2'));
  await shot(page, 'add');
  await page.getByRole('button', { name: 'Add 2 games' }).click();
  await settle(page);
  const rows = page.locator('.puzzle-list li');
  check('both games are listed', (await rows.count()) === 2);
  check('named by their players', (await text(rows.first())).includes('Kasparov – Topalov'));
  check('with what else is known', (await text(rows.first())).includes('1-0 · Hoogovens · 1999.01.20'));
  check('the add is reported', (await text(page.locator('.notice'))).includes('Added 2 games'));

  await page.locator('input[type="search"]').fill('club');
  check('search narrows the list', (await rows.count()) === 1 && (await text(rows.first())).includes('Me – Club friend'));
  await page.locator('input[type="search"]').fill('');
  await shot(page, 'collection');

  // ---- Viewing ----
  await rows.first().getByRole('button').click();
  await settle(page);
  const moves = page.locator('.game-moves');
  const current = page.locator('.game-moves [aria-current]');
  const strip = page.locator('.comment-strip');
  const nextMoves = page.locator('.game-next .next-move');
  check('a game opens on its starting position',
    (await current.count()) === 0 && (await text(nextMoves.first())) === '1. e4');
  const variation = moves.locator('.var');
  check('a variation is shown under its move',
    (await variation.count()) === 1 && (await text(variation)).includes('3... e5'));
  check('its comment is marked, not written out',
    (await variation.locator('.has-comment').count()) === 1 && !(await text(moves)).includes('the other way'));

  // ---- Fitting the phone ----
  const fit = await page.evaluate(() => {
    const board = document.querySelector('.game-board')?.getBoundingClientRect();
    const controls = document.querySelector('.game-controls')?.getBoundingClientRect();
    return {
      scrolls: document.scrollingElement.scrollHeight > window.innerHeight,
      boardWidth: board?.width ?? 0,
      controlsBottom: controls?.bottom ?? Infinity,
      smallest: Math.min(
        ...[...document.querySelectorAll('.game-controls button, .game-bar button')].map((b) => b.getBoundingClientRect().height),
      ),
    };
  });
  check(`the game fits the screen without scrolling (${JSON.stringify(fit)})`,
    !fit.scrolls && fit.boardWidth >= 380 && fit.controlsBottom <= 844 && fit.smallest >= 44);

  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  check('the arrow keys step through', (await text(current)) === 'd6');
  await variation.getByRole('button', { name: /^3\.\.\. e5/ }).click();
  check('tapping a variation move goes to it', (await text(current)) === '3... e5');
  check('and its comment shows above the list', (await text(strip)) === 'the other way');
  // After the move animation.
  await page.waitForTimeout(300);
  check('and the board shows it', (await page.locator('[data-square="e5"] svg').count()) === 1 && (await page.locator('[data-square="e7"] svg').count()) === 0);

  await page.getByRole('button', { name: 'Go to start' }).click();
  // 1. e4 d6 2. d4 Nf6 3. Nc3, then the choice between 3... g6 and 3... e5.
  for (let step = 0; step < 5; step++) await page.getByRole('button', { name: 'Next move' }).click();
  check(`the next moves offer the main line first (${(await nextMoves.allTextContents()).join(' | ')})`,
    (await nextMoves.allTextContents()).join(' | ') === '3... g6 | 3... e5');
  await nextMoves.nth(1).click();
  check('and the variation second', (await text(current)) === '3... e5');

  // ---- Playing a variation in ----
  await page.getByRole('button', { name: 'Go to start' }).click();
  await tap(page, 'c2');
  await tap(page, 'c4');
  await settle(page);
  const variations = await moves.locator('.var').allTextContents();
  check(`a move played at the start becomes a variation (${variations.join(' | ')})`,
    variations.some((v) => v.replace(/\s+/g, ' ').includes('1. c4')));
  check('and is the current move', (await text(current)) === '1. c4');

  await strip.click();
  await page.getByRole('dialog', { name: 'Comment' }).locator('textarea').fill('The English instead');
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await settle(page);
  check('a comment saves and shows above the moves', (await text(strip)) === 'The English instead');
  check('and marks its move', (await current.locator('.has-comment').count()) === 1);

  // A long press on a move offers what can be done with it.
  const c4 = moves.getByRole('button', { name: /^1\. c4/ });
  const box = await c4.boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(650);
  await page.mouse.up();
  const actions = page.getByRole('dialog', { name: 'Actions for 1. c4' });
  check('a long press opens the move\'s actions', await actions.isVisible());
  check('which say how much a delete would remove', (await text(actions)).includes('Delete from here1 move'));
  await actions.getByRole('button', { name: 'Make main line' }).click();
  await settle(page);
  const firstRow = moves.locator('.move-row').first();
  check(`the variation can become the main line (${await text(firstRow)})`,
    (await text(firstRow.locator('.move-cell').first())) === 'c4');
  await shot(page, 'game');

  // ---- Flip, and it stays flipped ----
  const a1Before = await squareCentre(page, 'a1');
  await page.getByRole('button', { name: 'Flip board' }).click();
  await settle(page);
  const a1After = await squareCentre(page, 'a1');
  check('flipping puts a1 at the top', a1After.y < a1Before.y);
  await page.reload();
  await settle(page);
  await page.getByRole('navigation').getByRole('button', { name: 'Games' }).click();
  await page.locator('.card').first().click();
  await page.locator('.puzzle-list li').first().getByRole('button').click();
  await settle(page);
  check('the flip survives a reload', (await squareCentre(page, 'a1')).y < a1Before.y);
  await page.getByRole('button', { name: 'Next move' }).click();
  check('so do the variation and comment',
    (await text(moves.locator('.var'))).includes('1. e4') && (await text(strip)) === 'The English instead');

  // ---- Details ----
  await page.getByRole('button', { name: 'Game actions' }).click();
  await page.getByRole('button', { name: /^Edit details/ }).click();
  await page.getByLabel('Black', { exact: true }).fill('Anand');
  await page.getByRole('button', { name: 'Save details' }).click();
  await settle(page);
  check('details save, and rename the game',
    await page.getByRole('heading', { name: 'Kasparov – Anand' }).isVisible());

  // ---- Export ----
  await page.getByRole('button', { name: 'Game actions' }).click();
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Download PGN' }).click(),
  ]);
  const exported = readFileSync(await download.path(), 'utf8');
  check('the download is the game as edited',
    exported.includes('[Black "Anand"]') && exported.includes('1. c4 {The English instead}') && exported.includes('(1. e4'));

  // ---- Moving and reordering ----
  await page.getByRole('button', { name: 'Back to Openings' }).click();
  await page.getByRole('button', { name: 'Back to games' }).click();
  page.once('dialog', (d) => d.accept('Keepers'));
  await page.getByRole('button', { name: 'New collection' }).click();
  await settle(page);
  await page.getByRole('button', { name: 'Back to games' }).click();
  await page.locator('.card', { hasText: 'Openings' }).click();

  await page.getByRole('button', { name: 'Reorder' }).click();
  await page.getByRole('button', { name: 'Move down' }).first().click();
  await settle(page);
  check('a game moves down', (await text(page.locator('.puzzle-list li').first())).includes('Me – Club friend'));

  await page.getByRole('button', { name: 'Select', exact: true }).click();
  await page.locator('.puzzle-list li').first().getByRole('button').click();
  await shot(page, 'select');
  await page.getByRole('button', { name: 'Move', exact: true }).click();
  await settle(page);
  check('a selected game moves to another collection', (await page.locator('.puzzle-list li').count()) === 1);
  await page.getByRole('button', { name: 'Back to games' }).click();
  const cards = await page.locator('.card').allTextContents();
  check(`and the counts follow (${cards.join(' | ')})`,
    cards.some((c) => c.includes('Openings') && c.includes('1 game')) &&
      cards.some((c) => c.includes('Keepers') && c.includes('1 game')));

  // ---- Offline ----
  await context.setOffline(true);
  await page.waitForTimeout(200);
  await page.locator('.card', { hasText: 'Openings' }).click();
  await page.locator('.puzzle-list li').first().getByRole('button').click();
  await settle(page);
  check('a game still opens offline', await page.locator('.game-moves').isVisible());
  check('but cannot be changed', await page.getByRole('button', { name: 'Flip board' }).isDisabled());
  await context.setOffline(false);
} catch (error) {
  console.log(`FAIL  threw: ${error.message.split('\n')[0]}`);
  await page.screenshot({ path: `${SHOTS ?? '/tmp'}/e2e-games-failure.png` }).catch(() => {});
  console.log('  at failure, page showed:',
    ((await page.locator('body').textContent().catch(() => '')) ?? '').replace(/\s+/g, ' ').trim().slice(0, 200));
  failures.push('exception');
} finally {
  await browser.close();
  await server.close();
}

if (failures.length) {
  console.log(`\n${failures.length} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
