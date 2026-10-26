// Draws the app icon and writes Resources/AppIcon.icns: the notch on an off-white sheet,
// with a live activity in the theme's orange under it and two quiet pills below.
// Usage: swift Scripts/make-icon.swift [preview.png]   (from the repository root; needs iconutil)
import AppKit

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func pill(_ rect: CGRect, _ hex: UInt32, in context: CGContext) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    context.setFillColor(color(hex))
    context.fillPath()
}

func drawIcon(side: Int) -> Data? {
    let size = CGFloat(side)
    guard let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // The plate: the rounded square macOS icons sit on, with the usual margin around it.
    let margin = size * 0.1
    let plate = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let platePath = CGPath(roundedRect: plate, cornerWidth: plate.width * 0.225, cornerHeight: plate.width * 0.225, transform: nil)
    context.addPath(platePath)
    context.setFillColor(color(0x141414))
    context.fillPath()

    // The sheet: the design's off-white ground, inset so the plate reads as a frame.
    let sheet = plate.insetBy(dx: plate.width * 0.07, dy: plate.width * 0.07)
    let sheetPath = CGPath(roundedRect: sheet, cornerWidth: sheet.width * 0.19, cornerHeight: sheet.width * 0.19, transform: nil)
    context.addPath(sheetPath)
    context.setFillColor(color(0xF7F5EF))
    context.fillPath()

    // The notch hangs from the sheet's top edge.
    let notchWidth = sheet.width * 0.5, notchHeight = sheet.height * 0.16
    context.saveGState()
    context.addPath(sheetPath)
    context.clip()
    let notch = CGRect(x: sheet.midX - notchWidth / 2, y: sheet.maxY - notchHeight, width: notchWidth, height: notchHeight * 2)
    context.addPath(CGPath(roundedRect: notch, cornerWidth: notchHeight * 0.5, cornerHeight: notchHeight * 0.5, transform: nil))
    context.setFillColor(color(0x141414))
    context.fillPath()
    context.restoreGState()

    // Under it: a live activity in the one orange, then a black pill and a beige one.
    let rowHeight = sheet.height * 0.13
    pill(CGRect(x: sheet.midX - sheet.width * 0.33, y: sheet.midY - rowHeight * 0.1, width: sheet.width * 0.66, height: rowHeight), 0xF2703E, in: context)
    let lower = sheet.midY - rowHeight * 1.75
    pill(CGRect(x: sheet.midX - sheet.width * 0.33, y: lower, width: sheet.width * 0.36, height: rowHeight), 0x1A1A1A, in: context)
    pill(CGRect(x: sheet.midX + sheet.width * 0.07, y: lower, width: sheet.width * 0.26, height: rowHeight), 0xE3DBCD, in: context)

    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AraNotch-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try drawIcon(side: points * scale)!.write(to: iconset.appendingPathComponent(name))
    }
}
// An argument asks for one large picture too, to look at.
if CommandLine.arguments.count > 1 {
    try drawIcon(side: 1024)!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try tool.run()
tool.waitUntilExit()
print(tool.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
