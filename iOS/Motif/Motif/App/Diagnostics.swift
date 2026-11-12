import SwiftUI
import OSLog
import UniformTypeIdentifiers

// iPhone Duo device checks (plan §8.7, "Diagnostics build"). Compiled into Debug builds, so CI
// compiles it, and into a TestFlight build run with the `diagnostics` input (-DMOTIF_DIAGNOSTICS).
// It records only in that TestFlight build, or with `-MotifDiagnostics YES` on a Debug launch:
// App Store builds don't contain it. Remove it, its call sites and the workflow input once the
// device checks are done.
#if DEBUG || MOTIF_DIAGNOSTICS

/// The diagnostics log: one line per event, to the unified log (`com.dthedy.Motif`, category
/// `duo`) and to a rotating file in Caches that the Account sheet exports.
enum Diag {
    static let enabled: Bool = {
        #if MOTIF_DIAGNOSTICS
        return true
        #else
        return UserDefaults.standard.bool(forKey: "MotifDiagnostics")
        #endif
    }()
    private static let logger = Logger(subsystem: "com.dthedy.Motif", category: "duo")
    private static let sink = DiagSink()
    static func log(_ tag: String, _ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        logger.log("[\(tag, privacy: .public)] \(text, privacy: .public)")
        sink.append("\(Date.now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))) [\(tag)] \(text)")
    }
    static func clear() { sink.clear(); log("app", "log cleared") }
    /// The header and every line kept, as one text file for the share sheet.
    static func export() -> URL { sink.export(header: header) }
    static var size: String { ByteCountFormatter.string(fromByteCount: Int64(sink.size), countStyle: .file) }

    private static var header: String {
        let info = Bundle.main.infoDictionary
        var machine = utsname(); uname(&machine)
        let model = withUnsafeBytes(of: &machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return """
        Motif diagnostics
        exported \(Date.now.formatted(.iso8601))
        app \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))
        device \(model), \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }
}

/// Writes lines on a serial queue; rotates at 4 MB, keeping one older file.
private final class DiagSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dthedy.Motif.diagnostics")
    private let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("motif-diagnostics.log")
    private var older: URL { url.deletingPathExtension().appendingPathExtension("1.log") }
    private let limit = 4_000_000
    var size: Int { queue.sync { fileSize(url) + fileSize(older) } }
    func append(_ line: String) {
        queue.async { [self] in
            if fileSize(url) > limit {
                try? FileManager.default.removeItem(at: older)
                try? FileManager.default.moveItem(at: url, to: older)
            }
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close()
            } else { try? data.write(to: url) }
        }
    }
    func clear() { queue.sync { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: older) } }
    func export(header: String) -> URL {
        queue.sync {
            let stamp = Date.now.formatted(Date.ISO8601FormatStyle()).replacingOccurrences(of: ":", with: "")
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("Motif-diagnostics-\(stamp).txt")
            var data = Data((header + "\n\n").utf8)
            for part in [older, url] { if let body = try? Data(contentsOf: part) { data.append(body) } }
            try? data.write(to: out)
            return out
        }
    }
    private func fileSize(_ file: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0 }
}

/// The export, made when the share sheet asks for it.
struct DiagnosticsFile: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in SentTransferredFile(Diag.export()) }
    }
}

private func pt(_ value: CGFloat) -> String { String(format: value == value.rounded() ? "%.0f" : "%.1f", value) }
private func rect(_ value: CGRect) -> String { "\(pt(value.minX)),\(pt(value.minY)) \(pt(value.width))x\(pt(value.height))" }
private func sizeClass(_ value: UserInterfaceSizeClass?) -> String {
    switch value { case .compact: "C"; case .regular: "R"; default: "?" }
}

/// Logs a view's layout whenever it changes: its frame on screen, safe area per edge, the
/// fold's active division in its own coordinates (and whether the view crosses it), plus,
/// with `traits`, the size classes and accessibility settings. `state` adds what the screen
/// holds (selection, path, session), so a fold can be checked for continuity.
private struct DiagProbe: ViewModifier {
    let name: String
    let traits: Bool
    let state: (() -> String)?
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        if Diag.enabled {
            content
                .onGeometryChange(for: String.self) { proxy in
                    let frame = proxy.frame(in: .global), insets = proxy.safeAreaInsets
                    var line = "frame \(rect(frame)) safe T\(pt(insets.top)) L\(pt(insets.leading)) B\(pt(insets.bottom)) R\(pt(insets.trailing))"
                    if let division = proxy.motifDivision {
                        let crosses = CGRect(origin: .zero, size: proxy.size).intersects(division)
                        line += " division \(rect(division))\(crosses ? " CROSSES" : " clear")"
                    }
                    return line
                } action: { line in
                    Diag.log("layout", "\(name) \(line)\(state.map { " | " + $0() } ?? "")")
                }
                .onChange(of: traitLine, initial: true) { _, line in if traits { Diag.log("traits", "\(name) \(line)") } }
                .background { if #available(iOS 27.1, *) { BarEdgeReporter(name: name) } }
        } else { content }
    }
    private var traitLine: String {
        "class \(sizeClass(horizontal))x\(sizeClass(vertical)) type \(typeSize) reduceTransparency \(reduceTransparency) contrast \(contrast == .increased ? "increased" : "standard") phase \(phase)"
    }
}
/// The side the vertical bars are on, which only iOS 27.1 reports.
@available(iOS 27.1, *)
private struct BarEdgeReporter: View {
    let name: String
    @Environment(\.toolbarVerticalEdge) private var edge
    var body: some View {
        Color.clear.onChange(of: edge.map { $0 == .leading ? "leading" : "trailing" } ?? "horizontal", initial: true) { _, side in
            Diag.log("bars", "\(name) \(side)")
        }
    }
}
extension View {
    func diagProbe(_ name: String, traits: Bool = false, state: (() -> String)? = nil) -> some View {
        modifier(DiagProbe(name: name, traits: traits, state: state))
    }
    /// One event when `value` changes, e.g. column visibility or a sheet opening.
    func diagChange<Value: Equatable>(_ tag: String, of value: Value, initial: Bool = false, _ describe: @escaping (Value) -> String) -> some View {
        onChange(of: value, initial: initial) { _, now in Diag.log(tag, describe(now)) }
    }
}

/// The Account sheet's Diagnostics section: export the log through the share sheet, or clear it.
struct DiagnosticsSection: View {
    @State private var cleared = 0
    var body: some View {
        if Diag.enabled {
            Section {
                ShareLink(item: DiagnosticsFile(), preview: SharePreview("Motif diagnostics")) {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }
                Button("Clear Diagnostics", systemImage: "trash", role: .destructive) { Diag.clear(); cleared += 1 }
            } header: { Text("Diagnostics") } footer: {
                Text("TestFlight only. Records layout, folds and timings for the iPhone Duo checks, no library content. \(Diag.size) kept.")
                    .id(cleared)
            }
        }
    }
}

#else
enum Diag {
    static let enabled = false
    @inline(__always) static func log(_ tag: String, _ message: @autoclosure () -> String) {}
}
extension View {
    @inline(__always) func diagProbe(_ name: String, traits: Bool = false, state: (() -> String)? = nil) -> some View { self }
    @inline(__always) func diagChange<Value: Equatable>(_ tag: String, of value: Value, initial: Bool = false, _ describe: @escaping (Value) -> String) -> some View { self }
}
struct DiagnosticsSection: View { var body: some View { EmptyView() } }
#endif
