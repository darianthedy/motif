import XCTest
@testable import Motif

@MainActor final class RootViewTests: XCTestCase {
    func testFourRootStatesNeverShowAnEmptyLibraryDuringLoad() async throws {
        let storage = testStorage(), defaults = UserDefaults(suiteName: "root-" + newID())!
        let store = LibraryStore(account: TestAccount(nil, MemoryBackend()), cache: Cache(storage: storage), outbox: Outbox(storage: storage), defaults: defaults)
        let app = AppState(store: store)
        XCTAssertEqual(app.root, .unknown)
        await store.open(); XCTAssertEqual(app.root, .signedOut)
        try await store.signIn("u", "p"); XCTAssertEqual(app.root, .library)
        app.tab = .account; await app.signOut(); XCTAssertEqual(app.root, .signedOut); XCTAssertEqual(app.tab, .puzzles)
        defaults.set(try JSONEncoder().encode(User(id: "u", email: "u")), forKey: "motif:user")
        let offline = LibraryStore(account: TestAccount(nil, MemoryBackend()), cache: Cache(storage: storage), outbox: Outbox(storage: storage), defaults: defaults, online: false)
        let waiting = AppState(store: offline)
        XCTAssertEqual(waiting.root, .waiting)
        // A brand-new device has no cache, so it remains a waiting screen offline.
        let emptyStorage = testStorage()
        let empty = LibraryStore(account: TestAccount(nil, MemoryBackend()), cache: Cache(storage: emptyStorage), outbox: Outbox(storage: emptyStorage), defaults: defaults, online: false)
        await empty.open(); XCTAssertEqual(AppState(store: empty).root, .waiting)
    }
    func testScreenshotSamplesAreBundledAndOnlyUsedInDebugAccount() async throws {
        let account = ScreenshotAccount(seed: true, signedIn: true)
        let current = await account.currentUser(), user = try XCTUnwrap(current)
        let backend = await account.backend(user), library = try await backend.load()
        XCTAssertEqual(library.collections.count, 2); XCTAssertGreaterThan(library.puzzles.count, 3)
        XCTAssertEqual(library.games.count, 1)
    }
}
