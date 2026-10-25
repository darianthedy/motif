import Foundation

/// Each test session registers an isolated responder through a header. The
/// synchronized registry avoids shared mutable Swift 6 test state.
final class MockHTTPRegistry: @unchecked Sendable {
    static let shared = MockHTTPRegistry()
    private let lock = NSLock()
    private var handlers: [String: @Sendable (URLRequest) throws -> (Int, [String: String], Data)] = [:]
    func register(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, [String: String], Data)) -> String {
        let id = UUID().uuidString
        lock.lock(); defer { lock.unlock() }; handlers[id] = handler
        return id
    }
    func response(_ request: URLRequest) throws -> (Int, [String: String], Data) {
        lock.lock()
        let handler = request.value(forHTTPHeaderField: "X-Motif-Test").flatMap { handlers[$0] }
        lock.unlock()
        guard let handler else { throw URLError(.badServerResponse) }
        return try handler(request)
    }
    func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; handlers.removeValue(forKey: id) }
}
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, headers, data) = try MockHTTPRegistry.shared.response(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []
    func append(_ request: URLRequest) -> Int {
        lock.lock(); defer { lock.unlock() }; storage.append(request); return storage.count
    }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return storage }
}
func mockSession(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, [String: String], Data)) -> (URLSession, String) {
    let id = MockHTTPRegistry.shared.register(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Motif-Test": id]
    return (URLSession(configuration: config), id)
}
