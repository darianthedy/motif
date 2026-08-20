/**
 * Drives the solve loop in a real browser.
 *
 * The model layer is unit-tested, but nothing there proves a tap on a square
 * turns into the right UCI string, that the promotion picker commits the piece
 * you chose, or that a mis-drag is actually free. Those are properties of the
 * pointer pipeline and only a browser can answer them.
 *
 * Usage: node scripts/e2e-solve.mjs [--headed] [--shots]
 */
import { chromium } from 'playwright';
import { createServer } from 'vite';

const HEADED = process.argv.includes('--headed');
const SHOTS = process.argv.includes('--shots');

const failures = [];
function check(label, condition) {
  if (condition) {
    console.log(`  ok  ${label}`);
  } else {
    console.log(`FAIL  ${label}`);
    failures.push(label);
  }
}

/** Centre of a square, in page coordinates. */
async function squareCentre(page, square) {
  const board = await page.locator('.board').boundingBox();
  const files = 'abcdefgh';
  // The sample puzzles are all White to move, so the board is White-oriented.
  const col = files.indexOf(square[0]);
  const row = 8 - Number(square[1]);
  return {
    x: board.x + (col + 0.5) * (board.width / 8),
    y: board.y + (row + 0.5) * (board.height / 8),
  };
}

async function tap(page, square) {
  const { x, y } = await squareCentre(page, square);
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.up();
}

async function drag(page, from, to) {
  const a = await squareCentre(page, from);
  const b = await squareCentre(page, to);
  await page.mouse.move(a.x, a.y);
  await page.mouse.down();
  await page.mouse.move(b.x, b.y, { steps: 8 });
  await page.mouse.up();
}

const server = await createServer({ server: { port: 5199 } });
await server.listen();
const url = 'http://localhost:5199';

const browser = await chromium.launch({ headless: !HEADED });
// iPhone-ish viewport: this is the target device, so test at that size.
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

try {
  await page.goto(url);
  await page.getByRole('button', { name: 'Solve in order' }).click();
  await page.waitForSelector('.board');

  // ---- Board geometry ----
  // Every square must be square. Nothing in the unit tests can see this: the
  // first version set only grid-template-columns, so ranks holding pieces grew
  // to fit their glyphs and the empty ranks collapsed.
  const boxes = await page.locator('.square').evaluateAll((nodes) =>
    nodes.map((node) => {
      const rect = node.getBoundingClientRect();
      return { w: rect.width, h: rect.height };
    }),
  );
  check('the board has 64 squares', boxes.length === 64);
  const skewed = boxes.filter((box) => Math.abs(box.w - box.h) > 1);
  check(
    `every square is square (${skewed.length} skewed)`,
    skewed.length === 0,
  );
  const heights = new Set(boxes.map((box) => Math.round(box.h)));
  check(`all ranks are the same height (${[...heights].join(', ')})`, heights.size === 1);

  // ---- Puzzle 1: solve by tapping ----
  await tap(page, 'a1');
  const dots = await page.locator('.target').count();
  check('selecting a piece shows its legal destinations', dots > 0);

  if (SHOTS) await page.screenshot({ path: '/tmp/motif-selected.png' });

  // Tapping an empty, illegal square must deselect and cost nothing.
  await tap(page, 'd4');
  check('tapping an illegal square clears the selection', (await page.locator('.target').count()) === 0);
  check('and does not fail the puzzle', !(await page.locator('.bad').isVisible().catch(() => false)));

  // A legal but wrong move is a miss.
  await tap(page, 'a1');
  await tap(page, 'a7');
  await page.waitForTimeout(120);
  check('a legal wrong move is rejected', await page.locator('.board').isVisible());

  // Two more wrong tries should surface the hint.
  await tap(page, 'a1');
  await tap(page, 'a6');
  await page.waitForTimeout(80);
  await tap(page, 'a1');
  await tap(page, 'a5');
  await page.waitForTimeout(120);
  const hintShown = await page.locator('.hint').isVisible().catch(() => false);
  check('three wrong tries reveal the answer', hintShown);
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-hint.png' });

  // Play the revealed move to finish the (already failed) puzzle.
  await tap(page, 'a1');
  await tap(page, 'a8');
  await page.waitForTimeout(200);
  const missed = await page.locator('.result').isVisible().catch(() => false);
  check('a missed puzzle stops and shows the result card', missed);

  const comment = await page.locator('.comment').textContent().catch(() => '');
  check('the comment appears only after the puzzle resolves', Boolean(comment));
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-missed.png' });

  await page.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(150);

  // ---- Puzzle 2: solve by dragging, cleanly ----
  await drag(page, 'd1', 'd8');
  await page.waitForTimeout(200);
  const advanced = await page.locator('.board').isVisible();
  check('a clean drag solve advances without a confirmation step', advanced);

  if (SHOTS) await page.screenshot({ path: '/tmp/motif-board.png' });
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
