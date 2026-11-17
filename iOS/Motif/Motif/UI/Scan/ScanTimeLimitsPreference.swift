import Foundation

/// The Scan tab's Time Limits switch (Scan plan §5): on by default, but off while VoiceOver or
/// Switch Control is running unless it was turned on by hand. Stored on the device only, as an
/// optional so "never touched" can follow the accessibility setting.
enum ScanTimeLimitsPreference {
    static let key = "scanTimeLimits"

    /// Whether hard limits apply: the stored choice, else on unless an assistive technology
    /// that makes time-boxed steps hard is running.
    static func enabled(stored: Bool?, voiceOver: Bool, switchControl: Bool) -> Bool {
        stored ?? !(voiceOver || switchControl)
    }
}
