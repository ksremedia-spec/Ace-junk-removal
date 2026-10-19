#if os(macOS)
import AppKit
import Foundation

/// Testing aid for the screenshot workflow. Launching the Mac app with
/// `-screenshot /path/to/file.png` makes it draw its own visible windows
/// (including an open sheet) into that file a few seconds after it starts,
/// then quit. It draws from inside the app, so it needs no screen-recording
/// permission. A plain-text log goes next to the image (`file.png.log`) so a
/// failed run says why. Normal launches have no such argument and nothing
/// happens.
enum WindowSnapshot {
    private static var scheduled = false
    private static var lines: [String] = []

    /// Safe to call more than once (at app start and when the window appears);
    /// the capture is scheduled only the first time.
    static func captureIfRequested() {
        guard !scheduled else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-screenshot"), index + 1 < args.count else { return }
        scheduled = true
        let url = URL(fileURLWithPath: args[index + 1])
        note("arguments: \(args.joined(separator: " "))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            NSApp.activate(ignoringOtherApps: true)
            if NSApp.windows.isEmpty {
                // No window was made at launch. Ask for one the way a click on
                // the Dock icon does; SwiftUI answers by opening the main window.
                note("no windows after 4 s; asking the app to reopen")
                let reopened = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
                note("reopen handled: \(reopened.map { String($0) } ?? "no delegate method")")
            }
            for window in NSApp.windows where !window.isVisible && window.frame.width > 50 && window.frame.height > 50 {
                note("ordering front: \(describe(window))")
                window.makeKeyAndOrderFront(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                capture(to: url)
                writeLog(next: url)
                NSApp.terminate(nil)
            }
        }
    }

    private static func note(_ text: String) {
        lines.append(text)
        FileHandle.standardError.write(Data(("WindowSnapshot: " + text + "\n").utf8))
    }

    private static func describe(_ window: NSWindow) -> String {
        let size = "\(Int(window.frame.width))x\(Int(window.frame.height))"
        return "\"\(window.title)\" \(size) visible=\(window.isVisible) sheet=\(window.isSheet) level=\(window.level.rawValue)"
    }

    private static func writeLog(next url: URL) {
        let logURL = url.appendingPathExtension("log")
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func capture(to url: URL) {
        let all = NSApp.windows
        note("windows: \(all.count)")
        for window in all { note("  " + describe(window)) }
        let windows = all.filter { $0.isVisible && $0.frame.width > 50 && $0.frame.height > 50 }
        guard !windows.isEmpty else { note("no visible window to draw"); return }

        // Union of all window frames, in screen points (origin bottom-left).
        let union = windows.dropFirst().reduce(windows[0].frame) { $0.union($1.frame) }
        let scale = windows[0].backingScaleFactor
        let pixelsWide = Int(union.width * scale)
        let pixelsHigh = Int(union.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            note("could not make a \(pixelsWide)x\(pixelsHigh) bitmap")
            return
        }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { note("could not make a graphics context"); return }

        // Everything below is in pixels, so the Retina detail is kept.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(pixelsWide), height: CGFloat(pixelsHigh)).fill()
        // Draw back-to-front so a sheet lands on top of its window.
        for window in windows.sorted(by: { $0.orderedIndex > $1.orderedIndex }) {
            // The content view's superview is the whole window chrome: title
            // bar, toolbar and content.
            guard let view = window.contentView?.superview ?? window.contentView else { note("no view in \(describe(window))"); continue }
            guard let cache = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { note("no cache for \(describe(window))"); continue }
            view.cacheDisplay(in: view.bounds, to: cache)
            let target = NSRect(x: (window.frame.origin.x - union.origin.x) * scale,
                                y: (window.frame.origin.y - union.origin.y) * scale,
                                width: window.frame.width * scale,
                                height: window.frame.height * scale)
            cache.draw(in: target)
            note("drew \(describe(window)) at \(Int(target.origin.x)),\(Int(target.origin.y))")
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { note("could not encode the PNG"); return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            note("wrote \(png.count) bytes to \(url.path)")
        } catch {
            note("write failed: \(error.localizedDescription)")
        }
    }
}
#endif
