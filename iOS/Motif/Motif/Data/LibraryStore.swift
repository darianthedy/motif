import Foundation
import Observation

enum SyncStatus: Equatable, Sendable { case idle, syncing, error(String) }

/// The database owns the library; this store keeps a replaceable server copy
/// plus durable play. Edits flush play first so reset/delete never resurrect it.
@Observable @MainActor
final class LibraryStore {
    private(set) var user: User?
    private(set) var userKnown = false
    private(set) var base: Library?
    private(set) var loaded = false
    private(set) var outboxRecords = OutboxRecords()
    var online = true
    private(set) var status = SyncStatus.idle
    var library: Library? { base.map { overlay($0, outboxRecords) } }
    var pending: Int { outboxRecords.count }
    @ObservationIgnored private let account: any Account
    @ObservationIgnored private let cache: Cache
    @ObservationIgnored private let outbox: Outbox
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var backend: (any Backend)?
    @ObservationIgnored private var generation = 0

    init(account: any Account, cache: Cache = Cache(), outbox: Outbox = Outbox(),
         defaults: UserDefaults = .standard, online: Bool = true) {
        self.account = account; self.cache = cache; self.outbox = outbox; self.defaults = defaults; self.online = online
        user = defaults.data(forKey: "motif:user").flatMap { try? JSONDecoder().decode(User.self, from: $0) }
        userKnown = user != nil
    }
    private func remember(_ user: User?) {
        if let user { defaults.set(try? JSONEncoder().encode(user), forKey: "motif:user") }
        else { defaults.removeObject(forKey: "motif:user") }
    }
    func open() async {
        let version = generation
        if online {
            let found = try? await account.currentUser()
            guard version == generation else { return }
            remember(found)
            if let found, found.id == user?.id, backend != nil {
                userKnown = true
                await refresh()
                return
            }
            await adopt(found)
        } else { await adopt(user) }
    }
    private func adopt(_ found: User?) async {
        generation += 1
        let version = generation
        user = found; userKnown = true; base = nil; outboxRecords = OutboxRecords(); loaded = false
        guard let found else { backend = nil; status = .idle; return }
        let selected = await account.backend(found)
        guard version == generation else { return }
        backend = selected
        let cached = await cache.load(found.id)
        do {
            let pending = try await outbox.read(found.id)
            guard version == generation else { return }
            base = cached; outboxRecords = pending; loaded = true
        } catch {
            guard version == generation else { return }
            status = .error(error.localizedDescription); loaded = true; base = cached
        }
        if online { await refresh() }
    }
    func flush() async throws {
        guard let user, let backend, online else { return }
        let version = generation
        let result = try await outbox.flush(user.id, backend)
        guard version == generation else { return }
        base = base.map { overlay($0, result.uploaded) }
        outboxRecords = result.outbox
    }
    func refresh() async {
        guard let user, let backend, online else { return }
        let version = generation
        status = .syncing
        do {
            try await flush()
            let fresh = try await backend.load()
            guard version == generation else { return }
            try await cache.save(user.id, fresh)
            let pending = try await outbox.read(user.id)
            guard version == generation else { return }
            base = fresh; outboxRecords = pending; status = .idle
        } catch { if version == generation { status = .error(error.localizedDescription) } }
    }
    func setOnline(_ value: Bool) async {
        let changed = online != value; online = value
        if changed && value { await open() }
    }
    func write(_ edit: @Sendable (any Backend) async throws -> Void) async throws {
        guard let backend, online else { throw DataFailure(message: "You're offline") }
        status = .syncing
        do { try await flush(); try await edit(backend) }
        catch { status = .error(error.localizedDescription); throw error }
        await refresh()
    }
    private func record(_ added: OutboxRecords) async throws {
        guard let user else { return }
        let version = generation
        outboxRecords.runs += added.runs; outboxRecords.attempts += added.attempts
        try await outbox.add(user.id, added)
        guard version == generation else { return }
        do { try await flush() }
        catch { status = .error(error.localizedDescription) }
    }
    func startRun(_ run: Run) async throws { try await record(OutboxRecords(runs: [run])) }
    func recordAttempt(_ attempt: Attempt) async throws { try await record(OutboxRecords(attempts: [attempt])) }
    func signIn(_ email: String, _ password: String, signUp: Bool = false) async throws {
        if signUp { try await account.signUp(email, password) } else { try await account.signIn(email, password) }
        let found = try await account.currentUser()
        remember(found); await adopt(found)
    }
    func signOut() async throws {
        try await account.signOut(); remember(nil); await adopt(nil)
    }
}
