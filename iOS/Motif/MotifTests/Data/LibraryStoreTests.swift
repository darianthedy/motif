import XCTest
@testable import Motif

@MainActor
final class LibraryStoreTests: XCTestCase {
    private func defaults(_ user: User? = User(id: "u", email: "e")) throws -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MotifTests." + newID())!
        if let user { defaults.set(try JSONEncoder().encode(user), forKey: "motif:user") }
        return defaults
    }
    func testOfflineOpenUsesRememberedUserCacheAndPendingPlay() async throws {
        let storage = testStorage(), cache = Cache(storage: storage), box = Outbox(storage: storage)
        try await cache.save("u", testDataLibrary()); try await box.add("u", OutboxRecords(attempts: [testDataAttempt()]))
        let store = LibraryStore(account: TestAccount(nil, MemoryBackend()), cache: cache, outbox: box,
                                 defaults: try defaults(), online: false)
        await store.open()
        XCTAssertEqual(store.user?.id, "u"); XCTAssertTrue(store.loaded)
        XCTAssertEqual(store.library?.attempts.count, 1); XCTAssertEqual(store.pending, 1)
        do { try await store.write { try await $0.resetProgress() }; XCTFail("Allowed offline edit") }
        catch { XCTAssertEqual(error.localizedDescription, "You're offline") }
    }
    func testFreshServerCopyReplacesCacheNeverMergesDeletedRows() async throws {
        let storage = testStorage(), cache = Cache(storage: storage)
        try await cache.save("u", testDataLibrary())
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), MemoryBackend()), cache: cache,
                                 outbox: Outbox(storage: storage), defaults: try defaults())
        await store.open()
        XCTAssertEqual(store.library?.puzzles, [])
        let cached = await cache.load("u"); XCTAssertEqual(cached?.puzzles, [])
    }
    func testWriteFlushesPlayBeforeResetAndNothingResurrectsIt() async throws {
        let storage = testStorage(), backend = LoggingBackend(), box = Outbox(storage: storage)
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), backend), cache: Cache(storage: storage),
                                 outbox: box, defaults: try defaults())
        await store.open()
        store.online = false
        try await store.startRun(testDataRun()); try await store.recordAttempt(testDataAttempt())
        XCTAssertEqual(store.pending, 2)
        store.online = true
        try await store.write { try await $0.resetProgress() }
        XCTAssertEqual(store.library?.attempts, []); XCTAssertEqual(store.library?.runs, []); XCTAssertEqual(store.pending, 0)
        let events = await backend.events.events
        let reset = try XCTUnwrap(events.firstIndex(of: "reset"))
        XCTAssertTrue(events[..<reset].contains("save")); XCTAssertTrue(events[..<reset].contains("attempts"))
        await store.refresh(); XCTAssertEqual(store.library?.attempts, [])
    }
    func testOfflineNewDeviceDoesNotFlashAnEmptyLibrary() async throws {
        let store = LibraryStore(account: TestAccount(nil, MemoryBackend()), cache: Cache(storage: testStorage()),
                                 outbox: Outbox(storage: testStorage()), defaults: try defaults(), online: false)
        await store.open(); XCTAssertTrue(store.loaded); XCTAssertNil(store.library); XCTAssertEqual(store.user?.id, "u")
    }
    func testAuthAndSignOutClearRootDataButKeepTheAccountCache() async throws {
        let storage = testStorage(), cache = Cache(storage: storage)
        let store = LibraryStore(account: TestAccount(nil, MemoryBackend(testDataLibrary())), cache: cache,
                                 outbox: Outbox(storage: storage), defaults: try defaults(nil))
        XCTAssertFalse(store.userKnown)
        await store.open(); XCTAssertTrue(store.userKnown); XCTAssertNil(store.user)
        try await store.signIn("me", "p", signUp: true)
        XCTAssertEqual(store.user?.id, "me"); XCTAssertNotNil(store.library)
        try await store.signOut(); XCTAssertNil(store.user); XCTAssertNil(store.library)
        let kept = await cache.load("me"); XCTAssertNotNil(kept)
    }
    func testCacheLegacyDefaultsCorruptionAndStoragePathContainment() async throws {
        let storage = testStorage(), url = storage.file("../user/name", "library.json")
        XCTAssertTrue(url.path.hasPrefix(storage.root.path + "/"))
        XCTAssertFalse(url.deletingLastPathComponent().lastPathComponent.contains("/"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"collections":[],"puzzles":[],"runs":[],"attempts":[]}"#.utf8).write(to: url)
        let cache = Cache(storage: storage), legacy = await cache.load("../user/name")
        XCTAssertEqual(legacy?.games, []); XCTAssertEqual(legacy?.gameCollections, [])
        try Data("bad".utf8).write(to: url)
        let corrupt = await cache.load("../user/name"); XCTAssertNil(corrupt)
    }
    func testDevAccountAndMemoryBackendSurviveRelaunch() async throws {
        let storage = testStorage(), suite = "MotifTests.dev." + newID()
        let first = DevAccount(storage: storage, suiteName: suite)
        try await first.signIn("e", "p")
        let current = await first.currentUser()
        let user = try XCTUnwrap(current), backend = await first.backend(user)
        try await backend.createCollections([Collection(id: "c", name: "C", createdAt: 0)])
        let second = DevAccount(storage: storage, suiteName: suite)
        let recalled = await second.currentUser(); XCTAssertEqual(recalled, user)
        let reopened = await second.backend(user), library = try await reopened.load()
        XCTAssertEqual(library.collections.map(\.id), ["c"])
    }
}
