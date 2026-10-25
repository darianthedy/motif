import Foundation

/// One configured URL derives both services, as neon-js does.
struct NeonEndpoints: Sendable {
    let auth: URL
    let rest: URL
    init(_ base: URL) {
        func derive(_ label: String, _ suffix: String) -> URL {
            var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            if let host = parts.host, let dot = host.firstIndex(of: ".") {
                parts.host = String(host[..<dot]) + "." + label + host[dot...]
            }
            parts.query = nil; parts.fragment = nil
            return parts.url!.appendingPathComponent(suffix)
        }
        auth = derive("neonauth", "auth"); rest = derive("apirest", "rest/v1")
    }
}

/// The session is a cookie, never a bearer session token. No Origin is sent.
/// The separate JWT authorizes the Data API and refreshes near expiry.
actor NeonAuth: Account, JWTProvider {
    let endpoints: NeonEndpoints
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let now: @Sendable () -> Date
    private var token: String?
    private var refreshTask: Task<String, Error>?

    init(baseURL: URL, session: URLSession? = nil, cookieStorage: HTTPCookieStorage = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        endpoints = NeonEndpoints(baseURL); self.cookieStorage = cookieStorage; self.now = now
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = cookieStorage; config.httpShouldSetCookies = true
            self.session = URLSession(configuration: config)
        }
    }
    private func request(_ route: String, method: String = "GET", body: Row? = nil) async throws -> Row {
        let url = endpoints.auth.appendingPathComponent(route)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw DataFailure(message: "No HTTP response") }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            result[String(describing: field.key)] = String(describing: field.value)
        }
        cookieStorage.setCookies(HTTPCookie.cookies(withResponseHeaderFields: headers, for: url), for: url, mainDocumentURL: nil)
        let object = data.isEmpty ? Row() : (try? JSONDecoder().decode(Row.self, from: data)) ?? [:]
        guard (200..<300).contains(response.statusCode) else {
            throw DataFailure(message: object["message"]?.text ?? "Authentication failed")
        }
        if let jwt = response.value(forHTTPHeaderField: "set-auth-jwt") { token = jwt }
        return object
    }
    func currentUser() async throws -> User? {
        let response = try await request("get-session")
        guard let user = response["user"]?.fields, let id = user["id"]?.text, !id.isEmpty else { return nil }
        return User(id: id, email: user["email"]?.text ?? "")
    }
    func signIn(_ email: String, _ password: String) async throws {
        token = nil
        _ = try await request("sign-in/email", method: "POST", body: ["email": .string(email), "password": .string(password)])
    }
    func signUp(_ email: String, _ password: String) async throws {
        token = nil
        _ = try await request("sign-up/email", method: "POST", body: [
            "email": .string(email), "password": .string(password),
            "name": .string(email.components(separatedBy: "@").first ?? ""),
        ])
    }
    func signOut() async throws {
        _ = try await request("sign-out", method: "POST", body: [:])
        token = nil
        refreshTask?.cancel(); refreshTask = nil
        if let host = endpoints.auth.host {
            for cookie in cookieStorage.cookies ?? [] {
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                if host == domain || host.hasSuffix("." + domain) { cookieStorage.deleteCookie(cookie) }
            }
        }
    }
    private func expiration(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(Row.self, from: data),
              let exp = payload["exp"]?.numeric else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
    func jwt(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token, let expiry = expiration(token), expiry.timeIntervalSince(now()) > 60 { return token }
        if let refreshTask { return try await refreshTask.value }
        let task = Task {
            let response = try await self.request("token")
            guard let token = response["token"]?.text else { throw DataFailure(message: "No authentication JWT") }
            return token
        }
        refreshTask = task
        defer { refreshTask = nil }
        let fresh = try await task.value
        token = fresh
        return fresh
    }
    func backend(_ user: User) -> any Backend {
        RestBackend(rest: PostgRESTClient(baseURL: endpoints.rest, auth: self, session: session), userId: user.id)
    }
}
