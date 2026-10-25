import Foundation

struct User: Hashable, Codable, Sendable { var id: String; var email: String }
protocol Account: Sendable {
    func currentUser() async throws -> User?
    func signIn(_ email: String, _ password: String) async throws
    func signUp(_ email: String, _ password: String) async throws
    func signOut() async throws
    func backend(_ user: User) async -> any Backend
}

/// Any credentials work without a configured endpoint. User and library are
/// durable, just as the web dev account survives reload.
actor DevAccount: Account {
    private let storage: StoragePaths
    private let defaults: UserDefaults
    private let userKey: String
    init(storage: StoragePaths = StoragePaths(), suiteName: String? = nil, userKey: String = "motif:dev:user") {
        self.storage = storage; defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.userKey = userKey
    }
    func currentUser() -> User? {
        defaults.data(forKey: userKey).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }
    func signIn(_ email: String, _ password: String) throws {
        defaults.set(try JSONEncoder().encode(User(id: email, email: email)), forKey: userKey)
    }
    func signUp(_ email: String, _ password: String) throws { try signIn(email, password) }
    func signOut() { defaults.removeObject(forKey: userKey) }
    func backend(_ user: User) -> any Backend { MemoryBackend(fileURL: storage.file(user.id, "dev-library.json")) }
}
