import AppKit

/// Diagnostics: renders this app's own visible windows to PNG files.
/// Draws the views directly, so it needs no screen-recording permission and sees no other app.
@MainActor
enum WindowSnapshot {
    static func writeAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView,
                  view.bounds.width > 0, view.bounds.height > 0,
                  let content = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: content)

            // Composite onto grey so a black notch on a transparent window stays visible.
            let image = NSImage(size: view.bounds.size, flipped: false) { rect in
                NSColor(white: 0.6, alpha: 1).setFill()
                rect.fill()
                content.draw(in: rect)
                return true
            }
            guard let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }

            let name = "\(index)-\(type(of: window))-\(Int(view.bounds.width))x\(Int(view.bounds.height)).png"
            try? png.write(to: directory.appendingPathComponent(name))
        }
        try? Data().write(to: directory.appendingPathComponent("done"))
    }
}
