import Foundation

/// How a scan went, step by step: `scan_attempts.detail`. Stats read only
/// this, so nothing here is a summary that could go stale.
struct ScanAttemptDetail: Equatable, Codable, Sendable {
    var steps = ScanSteps()
    var softMisses: [ScanSoftMiss] = []
    /// Why the puzzle failed; nil when it passed or was skipped.
    var failReason: ScanFailReason?

    init(steps: ScanSteps = ScanSteps(), softMisses: [ScanSoftMiss] = [], failReason: ScanFailReason? = nil) {
        self.steps = steps; self.softMisses = softMisses; self.failReason = failReason
    }

    private enum CodingKeys: String, CodingKey { case steps, softMisses, failReason }

    /// Written by a newer app, a soft miss or reason this one doesn't know is
    /// left out rather than losing the attempt: its result is its own column.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = try c.decodeIfPresent(ScanSteps.self, forKey: .steps) ?? ScanSteps()
        softMisses = (try c.decodeIfPresent([String].self, forKey: .softMisses) ?? [])
            .compactMap(ScanSoftMiss.init(rawValue:))
        failReason = (try c.decodeIfPresent(String.self, forKey: .failReason)).flatMap(ScanFailReason.init(rawValue:))
    }
}
