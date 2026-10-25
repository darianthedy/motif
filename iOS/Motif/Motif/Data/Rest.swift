import Foundation

enum JSONValue: Hashable, Codable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    var text: String? { if case .string(let v) = self { return v }; return nil }
    var numeric: Double? { if case .number(let v) = self { return v }; return nil }
    var boolean: Bool? { if case .bool(let v) = self { return v }; return nil }
    var items: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var fields: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    var filterText: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v ? String(format: "%.0f", v) : String(v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return "null"
        default: return ""
        }
    }
    static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
}
typealias Row = [String: JSONValue]
enum Filter: Sendable, Equatable {
    case eq(String, JSONValue), `in`(String, [JSONValue]), lt(String, JSONValue)
}
struct UpsertOptions: Sendable, Equatable {
    var onConflict: [String]
    var ignoreDuplicates = false
}
protocol Rest: Sendable {
    func select(_ table: String, _ filters: [Filter]) async throws -> [Row]
    func insert(_ table: String, _ rows: [Row], _ upsert: UpsertOptions?) async throws -> [Row]
    func update(_ table: String, _ patch: Row, _ filters: [Filter]) async throws
    func delete(_ table: String, _ filters: [Filter]) async throws
}
extension Rest {
    func select(_ table: String) async throws -> [Row] { try await select(table, []) }
    func insert(_ table: String, _ rows: [Row]) async throws -> [Row] { try await insert(table, rows, nil) }
}
let PAGE_SIZE = 1000
protocol JWTProvider: Sendable {
    func jwt(forceRefresh: Bool) async throws -> String
}

/// The small PostgREST subset used by the backend. Authorization comes from
/// cookie-based NeonAuth; a rejected bearer is refreshed and retried once.
struct PostgRESTClient: Rest {
    let baseURL: URL
    let auth: any JWTProvider
    let session: URLSession
    init(baseURL: URL, auth: any JWTProvider, session: URLSession = .shared) {
        self.baseURL = baseURL; self.auth = auth; self.session = session
    }
    private func quoted(_ value: JSONValue) -> String {
        let text = value.filterText
        guard text.contains(where: { ",()\"".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    private func request(_ table: String, _ method: String, _ filters: [Filter],
                         query: [URLQueryItem] = [], body: JSONValue? = nil,
                         prefer: String? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
        var items = query
        for filter in filters {
            switch filter {
            case .eq(let key, let value): items.append(URLQueryItem(name: key, value: "eq." + value.filterText))
            case .lt(let key, let value): items.append(URLQueryItem(name: key, value: "lt." + value.filterText))
            case .in(let key, let values): items.append(URLQueryItem(name: key, value: "in.(" + values.map(quoted).joined(separator: ",") + ")"))
            }
        }
        components.queryItems = items.isEmpty ? nil : items
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        for retry in 0...1 {
            request.setValue("Bearer " + (try await auth.jwt(forceRefresh: retry == 1)), forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw DataFailure(message: "No HTTP response") }
            if response.statusCode == 401 && retry == 0 { continue }
            guard (200..<300).contains(response.statusCode) else {
                let error = try? JSONDecoder().decode(Row.self, from: data)
                throw DataFailure(message: error?["message"]?.text ?? "HTTP \(response.statusCode)")
            }
            return data
        }
        throw DataFailure(message: "Authentication failed")
    }
    func select(_ table: String, _ filters: [Filter]) async throws -> [Row] {
        var all: [Row] = []
        var offset = 0
        while true {
            let data = try await request(table, "GET", filters, query: [
                URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "order", value: "id.asc"),
                URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "limit", value: String(PAGE_SIZE)),
            ])
            let page = try JSONDecoder().decode([Row].self, from: data)
            all += page
            if page.count < PAGE_SIZE { return all }
            offset += PAGE_SIZE
        }
    }
    func insert(_ table: String, _ rows: [Row], _ upsert: UpsertOptions?) async throws -> [Row] {
        var prefer = "return=representation,missing=default"
        var query: [URLQueryItem] = []
        if let upsert {
            query.append(URLQueryItem(name: "on_conflict", value: upsert.onConflict.joined(separator: ",")))
            prefer += upsert.ignoreDuplicates ? ",resolution=ignore-duplicates" : ",resolution=merge-duplicates"
        }
        let data = try await request(table, "POST", [], query: query, body: .array(rows.map(JSONValue.object)), prefer: prefer)
        return data.isEmpty ? [] : try JSONDecoder().decode([Row].self, from: data)
    }
    func update(_ table: String, _ patch: Row, _ filters: [Filter]) async throws {
        _ = try await request(table, "PATCH", filters, body: .object(patch))
    }
    func delete(_ table: String, _ filters: [Filter]) async throws { _ = try await request(table, "DELETE", filters) }
}
