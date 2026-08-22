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
const PIECES = readFileSync(new URL('../samples/missing-piece.json', import.meta.url), 'utf8');

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
  // A solve is a card too, not a flash: the comment and the line are the part
  // worth reading, and getting it right is when there is attention to read.
  const remainingBefore = Number(await page.locator('.count').textContent());
  await drag(page, 'd1', 'd8');
  await page.waitForTimeout(400);
  check('a clean drag solve stops on the result card',
    await page.locator('.result .good').isVisible().catch(() => false));
  check('showing the comment it withheld while solving',
    Boolean(await page.locator('.comment').textContent().catch(() => '')));
  const solvedLine = (await page.locator('.solution').first().textContent()) ?? '';
  check(`and the solution in SAN (${solvedLine.trim()})`, /d8/.test(solvedLine));
  check('and does not advance on its own',
    Number(await page.locator('.count').textContent()) === remainingBefore);
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-solved.png' });

  await page.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(400);
  const remainingAfter = Number(await page.locator('.count').textContent());
  check(`Continue moves to the next puzzle (${remainingBefore} to ${remainingAfter})`,
    remainingAfter < remainingBefore);

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
      { fen: '7k/5ppp/8/8/8/8/8/R6K w - - 0 1', solutions: [['a1a8']] },
      { fen: '6k1/5ppp/8/8/8/8/8/1R4K1 w - - 0 1', solutions: [['b1b8']] } ] },
    { collection: 'Chapter B', puzzles: [
      // Two accepted first moves, so the result card has more than one line to
      // disclose and has to mark the one actually played.
      { fen: '4r1k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1', solutions: [['e1e8'], ['e1d1']] } ] },
  ]);
  await page.getByRole('button', { name: 'Import puzzles' }).click();
  await page.locator('textarea').fill(multi);
  await page.waitForTimeout(300);
  check('a multi-collection file lists its chapters',
    (await page.locator('.groups li').count()) === 2);
  await page.getByRole('button', { name: /Add 3 puzzles/ }).click();
  await page.waitForTimeout(400);
  check('each chapter becomes its own collection',
    (await page.locator('.card').count()) === 3);

  // ---- Skipping ----
  // A puzzle you cannot play must never trap the session, so the escape hatch
  // is always present rather than only appearing for detected-broken puzzles.
  await page.getByText('Chapter A').click();
  await page.getByRole('button', { name: 'Solve in order' }).click();
  await page.waitForSelector('[data-square="a1"]');
  await page.waitForTimeout(300);
  const beforeSkip = Number(await page.locator('.count').textContent());
  await page.getByRole('button', { name: 'Skip' }).click();
  await page.waitForTimeout(600);
  const afterSkip = Number(await page.locator('.count').textContent());
  check(`skipping moves past the puzzle (${beforeSkip} to ${afterSkip})`, afterSkip < beforeSkip);
  await page.getByRole('button', { name: 'Stop' }).click();
  await page.waitForTimeout(400);
  const chapterCard = (await page.locator('.card').filter({ hasText: 'Chapter A' }).textContent()) ?? '';
  check(`a skip records neither a solve nor a miss (${chapterCard.replace(/\s+/g, ' ').trim()})`,
    /0 solved/.test(chapterCard) && !/to review/.test(chapterCard));

  // ---- Every solution, disclosed at the end ----
  await page.getByText('Chapter B').click();
  await page.getByRole('button', { name: 'Solve in order' }).click();
  await page.waitForSelector('[data-square="e1"]');
  await page.waitForTimeout(300);
  // The second line, not the mainline: the card must mark what was played.
  await drag(page, 'e1', 'd1');
  await page.waitForTimeout(400);
  const shownLines = await page.locator('.solution').count();
  check(`a solve discloses every accepted line (${shownLines})`, shownLines === 2);
  const playedIndex = await page.locator('.solution').evaluateAll((nodes) =>
    nodes.findIndex((node) => node.hasAttribute('data-played')),
  );
  check(`and marks the one played (line ${playedIndex + 1})`, playedIndex === 1);
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-solutions.png' });
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(400);
  check('finishing the last puzzle ends the session',
    await page.getByText('Session complete').isVisible().catch(() => false));
  await page.getByRole('button', { name: 'Done' }).click();
  await page.waitForTimeout(400);

  // ---- A line that ends on the opponent's move ----
  // Rd8+ and the king has exactly one square. The idea is the check and the box
  // it puts the king in, so the line is authored to stop after the forced reply
  // rather than demand a follow-up move that isn't the point.
  //
  // The claim only a browser can settle is the ordering. The runner reports the
  // reply and "finished" in the same breath, and a caller that reads either one
  // as the end of the story gets it wrong in a different way: honour the reply
  // and the puzzle never resolves, honour finished and the card is up before
  // the move it is talking about has been played. So: card absent immediately,
  // king on g7 and card present once the reply has landed.
  const endsOnReply = JSON.stringify({
    collection: 'Forced reply',
    puzzles: [
      {
        fen: '6k1/5p1p/8/8/8/8/8/3R2K1 w - - 0 1',
        solutions: [['d1d8', 'g8g7']],
        comment: 'Only square.',
      },
    ],
  });
  await page.getByRole('button', { name: 'Import puzzles' }).click();
  await page.locator('textarea').fill(endsOnReply);
  await page.waitForTimeout(300);
  await page.getByRole('button', { name: /Add 1 puzzle/ }).click();
  await page.waitForTimeout(400);
  await page.getByText('Forced reply').click();
  await page.getByRole('button', { name: 'Solve in order' }).click();
  await page.waitForSelector('[data-square="d1"]');
  await page.waitForTimeout(300);

  await drag(page, 'd1', 'd8');
  check('the puzzle does not resolve before the opponent has answered',
    !(await page.locator('.result').isVisible().catch(() => false)));

  await page.waitForTimeout(700);
  check('the scripted reply is played for you',
    (await page.locator('[data-square="g7"] svg').count()) === 1 &&
      (await page.locator('[data-square="g8"] svg').count()) === 0);
  check('and only then does the puzzle end, cleanly',
    await page.locator('.result .good').isVisible().catch(() => false));
  check('the comment it withheld appears as on any other puzzle',
    Boolean(await page.locator('.comment').textContent().catch(() => '')));
  const replyLine = (await page.locator('.solution').first().textContent()) ?? '';
  check(`and the line is shown through the reply (${replyLine.replace(/\s+/g, ' ').trim()})`,
    /Rd8\+/.test(replyLine) && /Kg7/.test(replyLine));
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-ends-on-reply.png' });

  await page.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(400);
  check('and Continue moves on exactly as it does elsewhere',
    await page.getByText('Session complete').isVisible().catch(() => false));
  await page.getByRole('button', { name: 'Done' }).click();
  await page.waitForTimeout(400);

  // ---- Missing piece ----
  // The other kind of puzzle: nothing to move, a piece to put back. The claims
  // worth checking in a browser are that the board stops being a move board,
  // that choosing a square and choosing a piece are two separate acts, and that
  // backing out of the second one is free.
  await page.getByRole('button', { name: 'Import puzzles' }).click();
  await page.locator('textarea').fill(PIECES);
  await page.waitForTimeout(300);
  await page.getByRole('button', { name: /Add 3 puzzles/ }).click();
  await page.waitForTimeout(400);
  await page.getByText('Missing pieces').click();
  await page.getByRole('button', { name: 'Solve in order' }).click();
  await page.waitForSelector('[data-square="g6"]');
  await page.waitForTimeout(300);

  await tap(page, 'g7');
  check('a square with a piece on it offers nothing to add',
    !(await page.locator('.picker').isVisible().catch(() => false)));
  await tap(page, 'h1');
  check('and a piece cannot be selected to move either',
    (await markedTargets(page)).length === 0);

  await tap(page, 'g6');
  check('an empty square asks which piece belongs there',
    await page.locator('.picker').isVisible().catch(() => false));
  check('offering a pawn as well as the promotion pieces',
    (await page.locator('.picker button').count()) === 6);
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-picker.png' });

  await page.getByRole('button', { name: 'Cancel' }).click();
  await page.waitForTimeout(200);
  check('cancelling puts nothing on the board',
    (await page.locator('[data-square="g6"] svg').count()) === 0);
  check('and costs nothing',
    !(await page.locator('.result').isVisible().catch(() => false)));

  await tap(page, 'g6');
  await page.getByRole('button', { name: 'Queen' }).click();
  await page.waitForTimeout(250);
  check('the right square with the wrong piece is a miss, not an answer',
    !(await page.locator('.result').isVisible().catch(() => false)));
  check('and still leaves the square empty',
    (await page.locator('[data-square="g6"] svg').count()) === 0);

  await tap(page, 'g6');
  await page.getByRole('button', { name: 'Knight' }).click();
  await page.waitForTimeout(300);
  check('the right piece resolves the puzzle',
    await page.locator('.result').isVisible().catch(() => false));
  check('and stands on the board where it belongs',
    (await page.locator('[data-square="g6"] svg').count()) === 1);
  check('the card names the answer',
    /Ng6/.test((await page.locator('.solution').textContent()) ?? ''));
  check('and shows the comment it withheld',
    /pins it/.test((await page.locator('.comment').textContent()) ?? ''));
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-missing-piece.png' });

  await page.getByRole('button', { name: 'Continue' }).click();
  await page.waitForTimeout(400);
  check('and the session moves on to the next one',
    await page.locator('[data-square="f8"]').isVisible());
  await page.getByRole('button', { name: 'Stop' }).click();
  await page.waitForTimeout(400);

  // ---- Puzzle detail ----
  // The one screen that shows a solution deliberately, and the only way to
  // correct a library built from OCR.
  await page.getByText('Back-rank mates').click();
  await page.getByRole('button', { name: 'Browse puzzles' }).click();
  await page.waitForTimeout(400);
  const rows = await page.locator('.puzzle-row').count();
  check(`browsing lists the collection's puzzles (${rows})`, rows === 3);

  await page.getByRole('button', { name: 'to review' }).first().click();
  await page.waitForTimeout(300);
  check('filtering narrows the list',
    (await page.locator('.puzzle-row').count()) < rows);
  await page.getByRole('button', { name: 'All' }).click();
  await page.waitForTimeout(200);

  await page.locator('.puzzle-row').first().click();
  await page.waitForSelector('.facts');
  await page.waitForTimeout(300);
  check('the detail view shows the solution in SAN',
    (await page.locator('.move').first().textContent()) === 'Ra8#');
  check('and the board renders the position',
    (await page.locator('[data-square]').count()) === 64);
  if (SHOTS) await page.screenshot({ path: '/tmp/motif-detail.png' });

  // Stepping through must actually change the position.
  const beforeStep = await page.locator('[data-square="a1"]').innerHTML();
  await page.locator('.move').first().click();
  await page.waitForTimeout(400);
  check('stepping to a move updates the board',
    (await page.locator('[data-square="a1"]').innerHTML()) !== beforeStep);

  // Editing a comment, then confirming it survives a round trip to storage.
  await page.locator('textarea').fill('Deflection, not a pin');
  await page.getByRole('button', { name: 'Save comment' }).click();
  await page.waitForTimeout(500);
  await page.reload();
  await page.waitForTimeout(900);
  await page.getByText('Back-rank mates').click();
  await page.getByRole('button', { name: 'Browse puzzles' }).click();
  await page.waitForTimeout(300);
  await page.locator('.puzzle-row').first().click();
  await page.waitForSelector('.facts');
  check('an edited comment persists',
    (await page.locator('textarea').inputValue()) === 'Deflection, not a pin');

  // Deleting removes it from the collection.
  page.once('dialog', (d) => d.accept());
  await page.getByRole('button', { name: 'Delete puzzle' }).click();
  await page.waitForTimeout(600);
  check(`deleting removes the puzzle (${rows} to ${await page.locator('.puzzle-row').count()})`,
    (await page.locator('.puzzle-row').count()) === rows - 1);
  await page.getByRole('button', { name: /← Back-rank mates/ }).click();
  await page.waitForTimeout(300);
  await page.getByRole('button', { name: '← Collections' }).click();
  await page.waitForTimeout(400);

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
  console.log(`FAIL  threw: ${error.message.split('\n')[0]}`);
  await page.screenshot({ path: '/tmp/e2e-failure.png' }).catch(() => {});
  console.log('  at failure, page showed:',
    ((await page.locator('body').textContent().catch(() => '')) ?? '').replace(/\s+/g, ' ').trim().slice(0, 160));
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
