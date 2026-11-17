/// What the Scan tab's stack pushes on its home: All Puzzles, then one puzzle.
enum ScanRoute: Hashable { case puzzles, puzzle(String) }
