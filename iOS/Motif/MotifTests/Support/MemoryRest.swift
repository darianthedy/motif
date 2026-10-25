import Foundation
@testable import Motif

/// A deterministic protocol test double, not an RLS/database test. Defaults,
/// upserts, foreign references and cascades exercise the native RestBackend.
actor MemoryRest: Rest {
    private var tables: [String: [Row]] = [:]
    private(set) var insertSizes: [String: [Int]] = [:]
    private func matches(_ row: Row, _ filters: [Filter]) -> Bool {
        filters.allSatisfy {
            switch $0 {
            case .eq(let key, let value): return row[key] == value
            case .in(let key, let values): return row[key].map(values.contains) ?? false
            case .lt(let key, let value): return (row[key]?.filterText ?? "") < value.filterText
            }
        }
    }
    func select(_ table: String, _ filters: [Filter]) -> [Row] { (tables[table] ?? []).filter { matches($0, filters) } }
    func insert(_ table: String, _ rows: [Row], _ upsert: UpsertOptions?) throws -> [Row] {
        insertSizes[table, default: []].append(rows.count)
        var returned: [Row] = []
        for var row in rows {
            row["user_id"] = row["user_id"] ?? .string("test")
            let keys = upsert?.onConflict ?? ["id"]
            let existing = (tables[table] ?? []).firstIndex { held in keys.allSatisfy { held[$0] == row[$0] } }
            if let existing {
                guard let upsert else { throw DataFailure(message: "Duplicate row") }
                if !upsert.ignoreDuplicates {
                    tables[table]![existing].merge(row) { _, incoming in incoming }
                    returned.append(tables[table]![existing])
                }
                continue
            }
            row["id"] = row["id"] ?? .string(newID())
            if table == "puzzles" || table == "games" { row["added_at"] = row["added_at"] ?? .string(isoTime(5000)) }
            if table == "puzzles" { row["flagged"] = row["flagged"] ?? .bool(false) }
            if table == "puzzles" || table == "games" {
                let parent = table == "puzzles" ? "collections" : "game_collections"
                if !(tables[parent] ?? []).contains(where: { $0["id"] == row["collection_id"] }) {
                    throw DataFailure(message: "No collection")
                }
            }
            tables[table, default: []].append(row)
            returned.append(row)
        }
        return returned
    }
    func update(_ table: String, _ patch: Row, _ filters: [Filter]) throws {
        if table == "games", let id = patch["collection_id"],
           !(tables["game_collections"] ?? []).contains(where: { $0["id"] == id }) { throw DataFailure(message: "No game collection") }
        for index in (tables[table] ?? []).indices where matches(tables[table]![index], filters) {
            tables[table]![index].merge(patch) { _, incoming in incoming }
        }
    }
    func delete(_ table: String, _ filters: [Filter]) {
        let removed = Set((tables[table] ?? []).filter { matches($0, filters) }.compactMap { $0["id"]?.text })
        tables[table] = (tables[table] ?? []).filter { !matches($0, filters) }
        if table == "collections" {
            delete("puzzles", [.in("collection_id", removed.map(JSONValue.string))])
        } else if table == "game_collections" {
            delete("games", [.in("collection_id", removed.map(JSONValue.string))])
        } else if table == "puzzles" {
            delete("attempts", [.in("puzzle_id", removed.map(JSONValue.string))])
        } else if table == "runs" {
            for index in (tables["attempts"] ?? []).indices {
                if let run = tables["attempts"]![index]["run_id"]?.text, removed.contains(run) {
                    tables["attempts"]![index]["run_id"] = .null
                }
            }
        }
    }
}
