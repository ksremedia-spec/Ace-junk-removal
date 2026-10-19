#if os(macOS)
import AppKit
import Foundation

/// Testing aid for the screenshot workflow. Launching the Mac app with
/// `-screenshot /path/to/file.png` makes it render its own visible windows
/// (including an open sheet) into that file a few seconds after it starts,
/// then quit. It draws from inside the app, so it needs no screen-recording
/// permission. Normal launches have no such argument and nothing happens.
enum WindowSnapshot {
    static func captureIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-screenshot"), index + 1 < args.count else { return }
        let path = args[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            capture(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    private static func capture(to url: URL) {
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 50 && $0.frame.height > 50 }
        guard !windows.isEmpty else { return }

        // Union of all window frames, in screen points (origin bottom-left).
        let union = windows.dropFirst().reduce(windows[0].frame) { $0.union($1.frame) }
        let scale = windows[0].backingScaleFactor
        let image = NSImage(size: union.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: union.size).fill()
        // Draw back-to-front so a sheet lands on top of its window.
        for window in windows.sorted(by: { $0.orderedIndex > $1.orderedIndex }) {
            // The content view's superview is the whole window chrome: title
            // bar, toolbar and content.
            guard let view = window.contentView?.superview ?? window.contentView else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let origin = NSPoint(x: window.frame.origin.x - union.origin.x, y: window.frame.origin.y - union.origin.y)
            rep.draw(in: NSRect(origin: origin, size: window.frame.size))
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return }
        // Keep the Retina pixel size so text stays sharp.
        _ = scale
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
    }
}
#endif
