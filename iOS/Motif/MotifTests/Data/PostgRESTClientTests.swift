import XCTest
@testable import Motif

actor TestJWT: JWTProvider {
    private(set) var forced: [Bool] = []
    func jwt(forceRefresh: Bool) -> String { forced.append(forceRefresh); return forceRefresh ? "fresh" : "cached" }
}
func testRequestBody(_ request: URLRequest) throws -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
        if read == 0 { break }
        data.append(contentsOf: buffer.prefix(read))
    }
    return data
}
final class PostgRESTClientTests: XCTestCase {
    func testSelectPagesUntilAShortPageAndQuotesFilters() async throws {
        let log = RequestLog()
        let (session, id) = mockSession { request in
            let n = log.append(request)
            let rows = n == 1 ? (0..<PAGE_SIZE).map { ["id": JSONValue.string(String($0))] } : [["id": .string("last")]]
            return (200, [:], try JSONEncoder().encode(rows))
        }
        defer { MockHTTPRegistry.shared.remove(id) }
        let client = PostgRESTClient(baseURL: URL(string: "https://example.test/rest/v1")!, auth: TestJWT(), session: session)
        let rows = try await client.select("puzzles", [.in("id", [.string("a,b"), .string("a\"b"), .string("plain")]), .eq("flagged", .bool(true)), .lt("position", .number(9))])
        XCTAssertEqual(rows.count, 1001); XCTAssertEqual(log.requests.count, 2)
        for (n, request) in log.requests.enumerated() {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value!) })
            XCTAssertEqual(values["select"], "*"); XCTAssertEqual(values["order"], "id.asc")
            XCTAssertEqual(values["offset"], String(n * 1000)); XCTAssertEqual(values["limit"], "1000")
            XCTAssertEqual(values["id"], #"in.("a,b","a\"b",plain)"#)
            XCTAssertEqual(values["flagged"], "eq.true"); XCTAssertEqual(values["position"], "lt.9")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cached")
            XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
        }
    }
    func testInsertShapesDefaultsAndBothUpsertModes() async throws {
        let log = RequestLog()
        let (session, id) = mockSession { r in _ = log.append(r); return (200, [:], try testRequestBody(r)) }
        defer { MockHTTPRegistry.shared.remove(id) }
        let client = PostgRESTClient(baseURL: URL(string: "https://example.test/rest/v1")!, auth: TestJWT(), session: session)
        let rows: [Row] = [["fen": .string("position")]]
        for option in [nil, UpsertOptions(onConflict: ["collection_id", "content_key"]), UpsertOptions(onConflict: ["id"], ignoreDuplicates: true)] {
            let returned = try await client.insert("puzzles", rows, option)
            XCTAssertEqual(returned, rows)
        }
        XCTAssertEqual(log.requests[0].value(forHTTPHeaderField: "Prefer"), "return=representation,missing=default")
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "Prefer"), "return=representation,missing=default,resolution=merge-duplicates")
        XCTAssertEqual(log.requests[2].value(forHTTPHeaderField: "Prefer"), "return=representation,missing=default,resolution=ignore-duplicates")
        XCTAssertEqual(URLComponents(url: log.requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "collection_id,content_key")
        XCTAssertEqual(log.requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertEqual(log.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testUpdateAndDeleteFiltersAndEmptyResponses() async throws {
        let log = RequestLog()
        let (session, id) = mockSession { r in _ = log.append(r); return (204, [:], Data()) }
        defer { MockHTTPRegistry.shared.remove(id) }
        let client = PostgRESTClient(baseURL: URL(string: "https://example.test/rest/v1")!, auth: TestJWT(), session: session)
        try await client.update("games", ["orientation": .string("b")], [.eq("id", .string("g"))])
        try await client.delete("games", [.in("id", [.string("g")])])
        XCTAssertEqual(log.requests.map(\.httpMethod), ["PATCH", "DELETE"])
        let patch = try JSONDecoder().decode(Row.self, from: testRequestBody(log.requests[0]))
        XCTAssertEqual(patch, ["orientation": .string("b")])
    }
    func test401RefreshesAndRetriesOnce() async throws {
        let log = RequestLog(), jwt = TestJWT()
        let (session, id) = mockSession { request in
            let n = log.append(request)
            return (n == 1 ? 401 : 200, [:], Data(n == 1 ? #"{"message":"expired"}"#.utf8 : "[]".utf8))
        }
        defer { MockHTTPRegistry.shared.remove(id) }
        let client = PostgRESTClient(baseURL: URL(string: "https://example.test")!, auth: jwt, session: session)
        _ = try await client.select("games")
        let forced = await jwt.forced
        XCTAssertEqual(forced, [false, true])
        XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
    }
    func testSecond401AndPostgrestMessagesAreSurfaced() async throws {
        let log = RequestLog()
        let (session, id) = mockSession { request in _ = log.append(request); return (401, [:], Data(#"{"message":"Denied"}"#.utf8)) }
        defer { MockHTTPRegistry.shared.remove(id) }
        let client = PostgRESTClient(baseURL: URL(string: "https://example.test")!, auth: TestJWT(), session: session)
        do { _ = try await client.select("games"); XCTFail("Ignored HTTP failure") }
        catch { XCTAssertEqual(error.localizedDescription, "Denied") }
        XCTAssertEqual(log.requests.count, 2)
    }
    func testChunkingAndTimestampRowBoundaries() async throws {
        XCTAssertEqual(isoTime(1234), "1970-01-01T00:00:01.234Z")
        XCTAssertEqual(try rowTime(.string("2024-03-01T12:34:56.123+00:00")), 1_709_296_496_123)
        let rest = MemoryRest(), backend = RestBackend(rest: rest, userId: "test")
        let c = GameCollection(id: "c", name: "C", createdAt: 0)
        try await backend.createGameCollections([c])
        try await backend.addGames((0..<405).map { NewGame(id: "g\($0)", collectionId: "c", position: $0, pgn: "*", orientation: .white) })
        let sizes = await rest.insertSizes
        XCTAssertEqual(sizes["games"], [200, 200, 5])
        let loaded = try await backend.load()
        XCTAssertEqual(loaded.games.count, 405)
    }
}
