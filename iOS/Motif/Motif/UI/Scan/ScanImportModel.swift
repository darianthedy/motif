import Foundation
import Observation

/// The Scan tab's import sheet: reads `{"version": 2, "scan": [ ... ]}` with `ScanImport`, the
/// same checks the loader uses, and upserts what passes into the pool.
@Observable @MainActor final class ScanImportModel {
    var text = ""
    var busy = false
    private(set) var result: ScanImport.Result?
    var incoming: Int { result?.puzzles.count ?? 0 }
    func parse() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = trimmed.isEmpty ? nil : ScanImport.read(trimmed)
    }
    func plan(_ library: Library) -> ScanImportBatch {
        let held = Set(library.scanPuzzles.map(\.contentKey))
        let puzzles = result?.puzzles ?? []
        return ScanImportBatch(puzzles: puzzles, added: puzzles.filter { !held.contains($0.contentKey) }.count,
                               rejected: result?.rejected.count ?? 0)
    }
    /// Written straight to the database, so it needs a connection, as puzzle imports do.
    func apply(_ app: AppState) async -> Bool {
        guard app.store.online, let library = app.store.library, incoming > 0, !busy else { return false }
        busy = true; defer { busy = false }
        let batch = plan(library)
        return await app.edit({ _ = try await $0.importScanPuzzles(batch.puzzles) }, done: batch.description)
    }
}
