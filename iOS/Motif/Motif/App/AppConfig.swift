import Foundation

/// The web and native clients share one optional, build-time Neon base URL.
/// Missing configuration selects the in-memory development backend.
enum AppConfig {
    static let neonBaseURL = neonBaseURL(in: Bundle.main.infoDictionary ?? [:])

    static func neonBaseURL(in info: [String: Any]) -> URL? {
        guard let value = info["NeonBaseURL"] as? String else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}
