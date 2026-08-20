/**
 * Drives the whole app in a real browser: import, solve, stop, reload, resume.
 *
 * The model layer is unit-tested, but nothing there proves a tap on a square
 * turns into the right UCI string, that the board is actually square, or that
 * a session survives a reload. Those are properties of the browser and only a
 * browser can answer them.
 *
 * Square positions are read from the real square elements rather than computed
 * by dividing the board box by eight. An earlier version did the latter, which
 * meant it silently assumed the very geometry a layout bug had broken, and
 * every check passed against a board that was visibly wrong on a phone.
 *
 * Usage: node scripts/e2e-solve.mjs [--headed] [--shots]
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { createServer } from 'vite';

const HEADED = process.argv.includes('--headed');
const SHOTS = process.argv.includes('--shots');
const SAMPLE = readFileSync(new URL('../samples/back-rank.json', import.meta.url), 'utf8');

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

async function drag(page, from, to) {
  const a = await squareCentre(page, from);
  const b = await squareCentre(page, to);
  await page.mouse.move(a.x, a.y);
  await page.mouse.down();
  await page.mouse.move(a.x, a.y - 5);
  await page.mouse.move(b.x, b.y, { steps: 12 });
  await page.mouse.up();
  await page.waitForTimeout(60);
}

/**
 * Squares carrying a legal-destination dot or capture ring.
 *
 * react-chessboard applies `squareStyles` to a child div of the square rather
 * than to the square itself, so the marker has to be read one level down.
 */
async function markedTargets(page) {
  return page.locator('[data-square]').evaluateAll((nodes) =>
    nodes
      .filter((node) =>
        [...node.children].some((child) =>
          (child.getAttribute('style') ?? '').includes('radial-gradient'),
        ),
      )
      .map((node) => node.dataset.square),
  );
}

async function selectedSquare(page) {
  const found = await page.locator('[data-square]').evaluateAll((nodes) =>
    nodes
      .filter((node) =>
        [...node.children].some((child) =>
          (child.getAttribute('style') ?? '').includes('255, 213, 79'),
        ),
      )
      .map((node) => node.dataset.square),
  );
  return found[0] ?? null;
}

const server = await createServer({ server: { port: 5199 } });
await server.listen();
const url = 'http://localhost:5199';

const browser = await chromium.launch({ headless: !HEADED });
// iPhone-ish viewport: this is the target device, so test at that size.
const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await context.newPage();

try {
  await page.goto(url);

  // ---- Import ----
  await page.getByRole('button', { name: 'Import puzzles' }).click();
  await page.locator('textarea').fill(SAMPLE);
  await page.waitForTimeout(200);
  check('the importer detects JSON and previews the count',
    await page.getByRole('button', { name: /Add 3 puzzles/ }).isVisible());
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-import.png' });

  await page.getByRole('button', { name: /Add 3 puzzles/ }).click();
  await page.waitForTimeout(300);
  check('the collection appears on the home screen',
    await page.getByText('Back-rank mates').isVisible());
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-home.png' });

  // Re-importing the same file must not duplicate anything.
  await page.getByRole('button', { name: 'Import puzzles' }).click();
  await page.locator('textarea').fill(SAMPLE);
  await page.waitForTimeout(200);
  await page.getByRole('button', { name: /Add 3 puzzles/ }).click();
  await page.waitForTimeout(300);
  check('re-importing adds nothing new',
    await page.getByText(/No new puzzles/).isVisible());
  const cards = await page.locator('.card').count();
  check('and does not create a second collection', cards === 1);

  // ---- Start a session ----
  await page.getByText('Back-rank mates').click();
  await page.getByRole('button', { name: 'Solve in order' }).click();
  await page.waitForSelector('[data-square="a1"]');
  await page.waitForTimeout(300);

  // ---- Board geometry ----
  const boxes = await page.locator('[data-square]').evaluateAll((nodes) =>
    nodes.map((node) => {
      const rect = node.getBoundingClientRect();
      return { w: rect.width, h: rect.height };
    }),
  );
  check('the board has 64 squares', boxes.length === 64);
  const skewed = boxes.filter((box) => Math.abs(box.w - box.h) > 1);
  check(`every square is square (${skewed.length} skewed)`, skewed.length === 0);
  const heights = new Set(boxes.map((box) => Math.round(box.h)));
  check(`all ranks are the same height (${[...heights].join(', ')})`, heights.size === 1);

  const svgCount = await page.locator('[data-square] svg').count();
  check(`pieces render as SVG (${svgCount} found)`, svgCount >= 6);

  // ---- Solving ----
  await tap(page, 'a1');
  const dots = await markedTargets(page);
  check(`selecting a piece shows its legal destinations (${dots.length})`, dots.length > 0);
  check('including the winning square', dots.includes('a8'));
  check('and marks the piece as selected', (await selectedSquare(page)) === 'a1');
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-selected.png' });

  await tap(page, 'd4');
  check('tapping an illegal square clears the selection', (await markedTargets(page)).length === 0);
  check('and does not fail the puzzle',
    !(await page.locator('.result').isVisible().catch(() => false)));

  for (const wrong of ['a7', 'a6', 'a5']) {
    await tap(page, 'a1');
    await tap(page, wrong);
  }
  check('three wrong tries reveal the answer',
    await page.locator('.hint').isVisible().catch(() => false));
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-hint.png' });

  await tap(page, 'a1');
  await tap(page, 'a8');
  await page.waitForTimeout(250);
  check('a missed puzzle stops and shows the result card',
    await page.locator('.result').isVisible().catch(() => false));
  check('the comment appears only after the puzzle resolves',
    Boolean(await page.locator('.comment').textContent().catch(() => '')));
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-missed.png' });

  await page.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(300);

  // ---- Clean solve by dragging ----
  const remainingBefore = Number(await page.locator('.count').textContent());
  await drag(page, 'd1', 'd8');
  // Longer than SOLVED_PAUSE_MS, or the auto-advance has not yet recorded it.
  await page.waitForTimeout(1200);
  const remainingAfter = Number(await page.locator('.count').textContent());
  check(`a clean drag solve advances by itself (${remainingBefore} to ${remainingAfter})`,
    remainingAfter < remainingBefore);
  check('with no confirmation step',
    !(await page.locator('.result').isVisible().catch(() => false)));

  // ---- Stop, reload, resume ----
  await page.getByRole('button', { name: 'Stop' }).click();
  await page.waitForTimeout(400);
  check('stopping returns to the collection list',
    await page.getByText('Back-rank mates').isVisible());
  check('and the collection is marked in progress',
    await page.locator('.pill').isVisible().catch(() => false));

  await page.reload();
  await page.waitForTimeout(600);
  check('the library survives a reload',
    await page.getByText('Back-rank mates').isVisible());
  check('the in-progress session survives a reload',
    await page.locator('.pill').isVisible().catch(() => false));
  const cardText = (await page.locator('.card').first().textContent()) ?? '';
  check(`and the solved puzzle is remembered (${cardText.trim()})`,
    /1 solved/.test(cardText));
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-resumed.png' });

  await page.getByText('Back-rank mates').click();
  await page.getByRole('button', { name: 'Resume' }).click();
  await page.waitForSelector('[data-square="a1"]');
  check('resuming reopens the board', await page.locator('[data-square="a1"]').isVisible());

  // ---- Review mistakes ----
  await page.getByRole('button', { name: 'Stop' }).click();
  await page.waitForTimeout(400);
  const reviewButton = page.getByRole('button', { name: /Review mistakes \(\d+\)/ });
  check('the missed puzzle is offered for review', await reviewButton.isVisible());

  // ---- Multi-collection file ----
  // Synthetic positions, not book content: a file may carry several chapters,
  // each becoming its own collection with no name asked for.
  const multi = JSON.stringify([
    { collection: 'Chapter A', puzzles: [
      { fen: '7k/5ppp/8/8/8/8/8/R6K w - - 0 1', solutions: [['a1a8']] } ] },
    { collection: 'Chapter B', puzzles: [
      { fen: '4r1k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1', solutions: [['e1e8']] } ] },
  ]);
  await page.getByRole('button', { name: 'Import puzzles' }).click();
  await page.locator('textarea').fill(multi);
  await page.waitForTimeout(300);
  check('a multi-collection file lists its chapters',
    (await page.locator('.groups li').count()) === 2);
  await page.getByRole('button', { name: /Add 2 puzzles/ }).click();
  await page.waitForTimeout(400);
  check('each chapter becomes its own collection',
    (await page.locator('.card').count()) === 3);

  // ---- Import from a URL ----
  // The dev server serves the repo root, so the sample is fetchable. This
  // checks the fetch-and-parse path, not the adding — the sample is already in
  // the library by now, which is why the preview counts rather than inserts.
  await page.getByRole('button', { name: 'Import puzzles' }).click();
  await page.locator('.url-row input').fill(`${url}/samples/back-rank.json`);
  await page.getByRole('button', { name: 'Fetch' }).click();
  await page.waitForTimeout(600);
  check('fetching a collection from a URL parses it',
    await page.getByRole('button', { name: /Add 3 puzzles/ }).isVisible());

  await page.locator('.url-row input').fill(`${url}/does-not-exist.json`);
  await page.getByRole('button', { name: 'Fetch' }).click();
  await page.waitForTimeout(600);
  // The dev server answers unknown paths with the SPA shell, status 200 —
  // the same shape as a share page or a login wall.
  const rejects = (await page.locator('.rejects').textContent().catch(() => '')) ?? '';
  check(`a URL returning a web page says so (${rejects.trim().slice(0, 40)}…)`,
    /web page, not a puzzle file/.test(rejects));
} catch (error) {
  console.log(`FAIL  threw: ${error.message}`);
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
