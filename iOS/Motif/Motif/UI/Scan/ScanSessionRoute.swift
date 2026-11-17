/// The open scan run, by scope (`SCOPE_ALL` or `SCOPE_REVIEW`), as `SessionRoute` is for puzzles.
struct ScanSessionRoute: Identifiable, Hashable { var scope: String; var id: String { scope } }
