#!/usr/bin/env swift
import AppKit
import WebKit

// Render the existing MIT vector knight into an opaque RGB app icon. No network
// resources are loaded; the retained SVG is the editable icon source.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("iOS/Motif/Motif/Resources")
let knightURL = resources.appendingPathComponent("Assets.xcassets/wN.imageset/wN.svg")
let knight = try String(contentsOf: knightURL, encoding: .utf8)
    .replacingOccurrences(of: "width=\"45\" height=\"45\"", with: "x=\"172\" y=\"108\" width=\"680\" height=\"680\"")
let vector = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<rect width="1024" height="1024" fill="#16171d"/>
<rect x="94" y="94" width="836" height="836" rx="100" fill="#24252c"/>
<path d="M194 810H830" stroke="#393b44" stroke-width="3"/>
<rect x="350" y="830" width="80" height="40" rx="8" fill="#7ac74f" opacity="0.45"/>
<rect x="472" y="830" width="80" height="40" rx="8" fill="#7ac74f" opacity="0.7"/>
<rect x="594" y="830" width="80" height="40" rx="8" fill="#7ac74f"/>
\(knight)
</svg>
"""
try vector.write(to: resources.appendingPathComponent("AppIcon.svg"), atomically: true, encoding: .utf8)

@MainActor final class Renderer: NSObject, WKNavigationDelegate {
    let output: URL
    init(output: URL) { self.output = output }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        configuration.snapshotWidth = 1024
        webView.takeSnapshot(with: configuration) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fputs("Icon snapshot failed: \(String(describing: error))\n", stderr); exit(1)
            }
            let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
            let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
            do { try bitmap.representation(using: .png, properties: [:])!.write(to: self.output); print(self.output.path); exit(0) }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
    }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    let renderer = Renderer(output: resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
    view.navigationDelegate = renderer
    view.loadHTMLString("<html><head><meta name='viewport' content='width=1024'></head><body style='margin:0;width:1024px;height:1024px'>\(vector)</body></html>", baseURL: nil)
    RunLoop.main.run()
}
