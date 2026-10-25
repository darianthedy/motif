import XCTest
@testable import Motif

func testJWT(_ exp: Int) -> String {
    let payload = Data("{\"exp\":\(exp)}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
    return "header.\(payload).signature"
}
final class NeonAuthTests: XCTestCase {
    func testEndpointsAndSignInSignUpShapesWithoutOrigin() async throws {
        let log = RequestLog()
        let (session, id) = mockSession { r in _ = log.append(r); return (200, [:], Data("{}".utf8)) }
        defer { MockHTTPRegistry.shared.remove(id) }
        let auth = NeonAuth(baseURL: URL(string: "https://ep.region.aws.neon.tech/neondb")!, session: session)
        try await auth.signIn("person@example.test", "test-password"); try await auth.signUp("person@example.test", "test-password")
        let body = try JSONDecoder().decode(Row.self, from: testRequestBody(log.requests[1]))
        XCTAssertEqual(body["name"], .string("person")); XCTAssertEqual(body["email"], .string("person@example.test"))
        XCTAssertEqual(log.requests[0].url?.absoluteString, "https://ep.neonauth.region.aws.neon.tech/neondb/auth/sign-in/email")
        XCTAssertEqual(NeonEndpoints(URL(string: "https://ep.region.aws.neon.tech/neondb")!).rest.absoluteString, "https://ep.apirest.region.aws.neon.tech/neondb/rest/v1")
        XCTAssertTrue(log.requests.allSatisfy { $0.value(forHTTPHeaderField: "Origin") == nil })
    }
    func testSessionHeaderJwtIsCapturedAndFreshTokenIsCached() async throws {
        let log = RequestLog(), token = testJWT(1000)
        let (session, id) = mockSession { r in
            _ = log.append(r)
            return (200, ["set-auth-jwt": token], Data(#"{"user":{"id":"u","email":"e"}}"#.utf8))
        }
        defer { MockHTTPRegistry.shared.remove(id) }
        let auth = NeonAuth(baseURL: URL(string: "https://session.example.test/db")!, session: session, now: { Date(timeIntervalSince1970: 100) })
        let user = try await auth.currentUser(), jwt = try await auth.jwt()
        XCTAssertEqual(user, User(id: "u", email: "e")); XCTAssertEqual(jwt, token)
        XCTAssertEqual(log.requests.count, 1)
    }
    func testNearExpiryRefreshAndConcurrentRequestsUseOneTokenCall() async throws {
        let log = RequestLog(), fresh = testJWT(1000)
        let (session, id) = mockSession { r in
            _ = log.append(r)
            if r.url!.path.hasSuffix("get-session") { return (200, ["set-auth-jwt": testJWT(150)], Data(#"{"user":{"id":"u"}}"#.utf8)) }
            return (200, [:], Data("{\"token\":\"\(fresh)\"}".utf8))
        }
        defer { MockHTTPRegistry.shared.remove(id) }
        let auth = NeonAuth(baseURL: URL(string: "https://refresh.example.test/db")!, session: session, now: { Date(timeIntervalSince1970: 100) })
        _ = try await auth.currentUser()
        async let a = auth.jwt(); async let b = auth.jwt()
        let tokens = try await [a, b]
        XCTAssertEqual(tokens, [fresh, fresh])
        XCTAssertEqual(log.requests.filter { $0.url!.path.hasSuffix("/token") }.count, 1)
    }
    func testAuthErrorsUseTheServiceMessage() async throws {
        let (session, id) = mockSession { _ in (400, [:], Data(#"{"message":"Wrong password","code":"INVALID"}"#.utf8)) }
        defer { MockHTTPRegistry.shared.remove(id) }
        let auth = NeonAuth(baseURL: URL(string: "https://error.example.test/db")!, session: session)
        do { try await auth.signIn("e", "p"); XCTFail("Ignored error") }
        catch { XCTAssertEqual(error.localizedDescription, "Wrong password") }
    }
    func testCookiesAreStoredAndSignOutClearsAuthCookiesAndJwt() async throws {
        let log = RequestLog(), token = testJWT(1000)
        let (session, id) = mockSession { r in
            _ = log.append(r)
            if r.url!.path.hasSuffix("get-session") {
                return (200, ["Set-Cookie": "session=fixture; Path=/; Secure; HttpOnly", "set-auth-jwt": token], Data(#"{"user":{"id":"u"}}"#.utf8))
            }
            if r.url!.path.hasSuffix("/token") { return (401, [:], Data(#"{"message":"Signed out"}"#.utf8)) }
            return (200, [:], Data("{}".utf8))
        }
        defer { MockHTTPRegistry.shared.remove(id) }
        let auth = NeonAuth(baseURL: URL(string: "https://cookie.example.test/db")!, session: session, now: { Date(timeIntervalSince1970: 100) })
        _ = try await auth.currentUser()
        let url = URL(string: "https://cookie.neonauth.example.test/db/auth")!
        XCTAssertTrue(HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "session" } == true)
        try await auth.signOut()
        XCTAssertFalse(HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "session" } == true)
        do { _ = try await auth.jwt(); XCTFail("JWT survived sign-out") } catch {}
    }
}
