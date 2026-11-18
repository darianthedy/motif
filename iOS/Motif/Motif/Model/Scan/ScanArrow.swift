import Foundation

/// A check, capture or threat the full scan should find (format v2).
struct ScanArrow: Hashable, Codable, Sendable {
    enum Side: String, Codable, CaseIterable, Sendable { case own, theirs }
    enum Kind: String, Codable, CaseIterable, Sendable { case check, capture, threat }

    var from: String
    var to: String
    var side: Side
    var kind: Kind
    /// Drawing it counts as found; leaving it out is not a miss (v4 quiet threats).
    /// Absent in the file = required.
    var optional: Bool = false

    init(from: String, to: String, side: Side, kind: Kind, optional: Bool = false) {
        self.from = from; self.to = to; self.side = side; self.kind = kind; self.optional = optional
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        side = try c.decode(Side.self, forKey: .side)
        kind = try c.decode(Kind.self, forKey: .kind)
        optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from); try c.encode(to, forKey: .to)
        try c.encode(side, forKey: .side); try c.encode(kind, forKey: .kind)
        if optional { try c.encode(true, forKey: .optional) }
    }

    private enum CodingKeys: String, CodingKey { case from, to, side, kind, optional }
}

extension ScanArrow {
    /// From + to squares ("f3g5"): how arrows are compared and stored in
    /// `ScanAttemptDetail`. Side and kind follow from the squares.
    var line: String { from + to }
}
