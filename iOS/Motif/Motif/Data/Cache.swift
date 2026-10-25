import Foundation

/// Application Support is durable and backed up. Each account's paths are
/// contained in its own directory, including dev ids that are email addresses.
struct StoragePaths: Sendable {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Motif", isDirectory: true)
    }
    func file(_ userId: String, _ name: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_@"))
        let safe = userId.addingPercentEncoding(withAllowedCharacters: allowed) ?? Data(userId.utf8).base64EncodedString()
        return root.appendingPathComponent(safe.isEmpty ? "%00" : safe, isDirectory: true).appendingPathComponent(name)
    }
}
/// Read-only server copy: replace, never merge. Losing/corrupting it costs
/// only an offline open; the outbox is kept separately.
actor Cache {
    let storage: StoragePaths
    init(storage: StoragePaths = StoragePaths()) { self.storage = storage }
    func load(_ userId: String) -> Library? {
        guard let data = try? Data(contentsOf: storage.file(userId, "library.json")) else { return nil }
        return try? JSONDecoder().decode(Library.self, from: data)
    }
    func save(_ userId: String, _ library: Library) throws {
        let url = storage.file(userId, "library.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: url, options: .atomic)
    }
}
