# iPhone Duo mockup canvases (plan Phase 4)

Open any page in a browser. Each has a tab per screen, a coverage grid, notes with
the §6 check, and a dark mode toggle.

- `analysis.html`: S15 Analysis view, S10 Puzzle analysis, S17 on S15
- `session.html`: S09 Session, S08 Puzzle detail, S17 on S09
- `shell.html`: S01 Launch, S02 Sign in, S03 Account, S04 / S11 homes, S17 on S04
- `lists.html`: S06 Collection, S07 Puzzle list, S12 Game collection
- `sheets.html`: S05 Import puzzles, S13 Import PGN, S14 New Game, S16 comment / details

`kit.js` and `kit.css` hold the shared components, the configurations measured in
Phase 1 (`CFG`) and the board layout rule (`boardGeom`). Every frame is generated
from the state table in its canvas file.

Render frames to PNG (Playwright from the main checkout):

    PLAYWRIGHT_FROM=<repo>/node_modules/ node render.mjs analysis.html out/ "s15:#S15a·O" "s15:row:S15c"
    PLAYWRIGHT_FROM=<repo>/node_modules/ node sheet.mjs out/sheet.png 600 out/*.png

Pair captures with frames (D09, `ios-duo-capture.yml`): `cells.mjs` lists each pose's
drawn cells and their frames; `pair.mjs` renders them and writes capture | mockup sheets.

    node cells.mjs plan IP
    PLAYWRIGHT_FROM=<repo>/node_modules/ node pair.mjs <captures dir> out/
