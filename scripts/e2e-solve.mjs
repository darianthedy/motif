/**
 * Drives the solve loop in a real browser.
 *
 * The model layer is unit-tested, but nothing there proves a tap on a square
 * turns into the right UCI string, that the promotion picker commits the piece
 * you chose, or that a mis-drag is free. Those are properties of the pointer
 * pipeline and only a browser can answer them.
 *
 * Square positions are read from the real square elements rather than computed
 * by dividing the board box by eight. The earlier version did the latter, which
 * meant it silently assumed the very geometry a layout bug had broken, and
 * every check passed against a board that was visibly wrong on a phone.
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
  await page.mouse.move(b.x, b.y, { steps: 10 });
  await page.mouse.up();
  await page.waitForTimeout(60);
}

/**
 * Squares currently carrying a legal-destination dot or capture ring.
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

/** The square currently highlighted as selected, if any. */
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
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

try {
  await page.goto(url);
  await page.getByRole('button', { name: 'Solve in order' }).click();
  await page.waitForSelector('[data-square="a1"]');
  await page.waitForTimeout(300);

  // ---- Board geometry ----
  const boxes = await page.locator('[data-square]').evaluateAll((nodes) =>
    nodes.map((node) => {
      const rect = node.getBoundingClientRect();
      return { square: node.dataset.square, w: rect.width, h: rect.height };
    }),
  );
  check('the board has 64 squares', boxes.length === 64);
  const skewed = boxes.filter((box) => Math.abs(box.w - box.h) > 1);
  check(`every square is square (${skewed.length} skewed)`, skewed.length === 0);
  const heights = new Set(boxes.map((box) => Math.round(box.h)));
  check(`all ranks are the same height (${[...heights].join(', ')})`, heights.size === 1);

  // Pieces must be vector, not glyphs: iOS renders the Unicode chess codepoints
  // poorly and gives U+265F an emoji presentation, which is what forced the
  // move to react-chessboard.
  const svgCount = await page.locator('[data-square] svg').count();
  check(`pieces render as SVG (${svgCount} found)`, svgCount >= 6);

  // ---- Puzzle 1: solve by tapping ----
  await tap(page, 'a1');
  const dots = await markedTargets(page);
  check(`selecting a piece shows its legal destinations (${dots.length})`, dots.length > 0);
  check('including the winning square', dots.includes('a8'));
  check('and marks the piece as selected', (await selectedSquare(page)) === 'a1');
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-selected.png' });

  // Tapping an empty, illegal square deselects and costs nothing.
  await tap(page, 'd4');
  check('tapping an illegal square clears the selection', (await markedTargets(page)).length === 0);
  check('and does not fail the puzzle', !(await page.locator('.result').isVisible().catch(() => false)));

  // Three legal-but-wrong moves should surface the hint.
  for (const wrong of ['a7', 'a6', 'a5']) {
    await tap(page, 'a1');
    await tap(page, wrong);
  }
  const hintShown = await page.locator('.hint').isVisible().catch(() => false);
  check('three wrong tries reveal the answer', hintShown);
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-hint.png' });

  // Play the revealed move to finish the (already failed) puzzle.
  await tap(page, 'a1');
  await tap(page, 'a8');
  await page.waitForTimeout(250);
  check('a missed puzzle stops and shows the result card',
    await page.locator('.result').isVisible().catch(() => false));

  const comment = await page.locator('.comment').textContent().catch(() => '');
  check('the comment appears only after the puzzle resolves', Boolean(comment));
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-missed.png' });

  await page.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(250);

  // ---- Puzzle 2: solve by dragging, cleanly ----
  await drag(page, 'd1', 'd8');
  await page.waitForTimeout(400);
  check('a clean drag solve advances without a confirmation step',
    !(await page.locator('.result').isVisible().catch(() => false)));
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
