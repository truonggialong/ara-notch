import AppKit
import CaptureCore
import CoreImage
import Vision

/// Takes a picture of a part of the screen with the system's own capture tool, which brings
/// its own selection crosshair. macOS shows other apps' windows only when the user has
/// allowed Screen Recording for this app.
@MainActor
enum ScreenCapturer {
    /// Whether macOS lets this app see other apps' windows.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Lets the user drag out a region (or press Space for a window). Answers on the main
    /// actor with the picture, or nil when the user pressed Escape.
    static func captureRegion(completion: @escaping @MainActor (CGImage?) -> Void) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-capture-\(UUID().uuidString).png")
        run(arguments: ["-i", "-x", "-t", "png", file.path], output: file, completion: completion)
    }

    /// Captures a fixed rectangle (in screen points, origin top left) without asking the user;
    /// for automated checks.
    static func capture(rect: CGRect, completion: @escaping @MainActor (CGImage?) -> Void) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-capture-\(UUID().uuidString).png")
        let region = [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0)) }.joined(separator: ",")
        run(arguments: ["-x", "-t", "png", "-R", region, file.path], output: file, completion: completion)
    }

    /// Outside the main actor on purpose: the process reports its end on a queue of its own.
    private nonisolated static func run(
        arguments: [String], output: URL, completion: @escaping @MainActor (CGImage?) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { _ in
            let image = CaptureImage.load(output)
            try? FileManager.default.removeItem(at: output)
            Task { @MainActor in completion(image) }
        }
        do {
            try process.run()
        } catch {
            Task { @MainActor in completion(nil) }
        }
    }
}

/// Reading and writing capture pictures.
enum CaptureImage {
    /// Reads the whole file into memory first. A picture made straight from a file is only
    /// decoded when it is first drawn, and a capture's temporary file is gone by then.
    static func load(_ file: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// Reads the text in a picture, on this Mac, with the Vision framework.
enum TextRecognizer {
    /// Answers on the main actor with the text in reading order; empty when none was found.
    nonisolated static func recognize(in image: CGImage, completion: @escaping @MainActor (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = recognizeNow(in: image)
            Task { @MainActor in completion(text) }
        }
    }

    nonisolated static func recognizeNow(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Vietnamese first where the system knows it; English is always there.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = ["vi-VT", "en-US"].filter(supported.contains)
        if !wanted.isEmpty {
            request.recognitionLanguages = wanted
        }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { observation -> RecognizedLines.Line? in
            guard let best = observation.topCandidates(1).first else { return nil }
            return RecognizedLines.Line(text: best.string, box: observation.boundingBox)
        }
        return RecognizedLines.text(lines)
    }
}

/// Cuts the subject of a picture out of its background, on this Mac, with the Vision framework.
enum SubjectCutout {
    /// Answers on the main actor with PNG data that is transparent around the subject, or nil
    /// when the picture cannot be read or no subject stands out.
    nonisolated static func cutOut(from imageData: Data, completion: @escaping @MainActor (Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = cutOutNow(from: imageData)
            Task { @MainActor in completion(result) }
        }
    }

    nonisolated static func cutOutNow(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
            let masked = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(masked, from: masked.extent) else { return nil }
            return CaptureImage.pngData(output)
        } catch {
            return nil
        }
    }
}

/// Draws annotations. The context's origin must be at the top left, y growing downwards.
@MainActor
enum AnnotationDrawing {
    /// - Parameter image: the picture under the annotations, which a blur takes its blocks from.
    static func draw(_ annotations: [Annotation], over image: CGImage? = nil, in context: CGContext) {
        for annotation in annotations {
            draw(annotation, over: image, in: context)
        }
    }

    /// The part of the picture under `box`, reduced to a few flat blocks.
    private static func mosaic(of image: CGImage, box: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = box.integral.intersection(bounds)
        guard area.width >= 1, area.height >= 1, let part = image.cropping(to: area) else { return nil }
        let blocks = MosaicGeometry.blocks(for: area.size)
        guard let small = CGContext(
            data: nil, width: blocks.columns, height: blocks.rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        small.interpolationQuality = .medium
        small.draw(part, in: CGRect(x: 0, y: 0, width: blocks.columns, height: blocks.rows))
        return small.makeImage()
    }

    private static func draw(_ annotation: Annotation, over image: CGImage?, in context: CGContext) {
        let color = CGColor(
            srgbRed: annotation.color.red, green: annotation.color.green, blue: annotation.color.blue, alpha: 1)
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.shape {
        case .arrow(let from, let to):
            let (left, right) = ArrowGeometry.head(from: from, to: to, length: annotation.lineWidth * 4.5)
            context.move(to: from)
            context.addLine(to: to)
            context.move(to: left)
            context.addLine(to: to)
            context.addLine(to: right)
            context.strokePath()
        case .line(let from, let to):
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        case .rectangle(let box):
            context.stroke(box)
        case .ellipse(let box):
            context.strokeEllipse(in: box)
        case .blur(let box):
            guard let image, let blocks = mosaic(of: image, box: box) else {
                // No picture to take blocks from: a flat grey box hides just as well.
                context.setFillColor(CGColor(gray: 0.5, alpha: 1))
                context.fill(box)
                return
            }
            let area = box.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.saveGState()
            context.interpolationQuality = .none
            // Pictures are drawn bottom up; turn this one back the right way.
            context.translateBy(x: area.minX, y: area.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(blocks, in: CGRect(origin: .zero, size: area.size))
            context.restoreGState()
        case .step(let number, let point):
            let radius = annotation.lineWidth * 3.2
            let disc = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
            context.fillEllipse(in: disc)
            // Dark numerals on a light disc, light ones on a dark disc.
            let luminance = 0.2126 * annotation.color.red + 0.7152 * annotation.color.green + 0.0722 * annotation.color.blue
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: radius * 1.15, weight: .bold),
                .foregroundColor: luminance > 0.6 ? NSColor.black : NSColor.white,
            ]
            let numeral = NSAttributedString(string: String(number), attributes: attributes)
            let size = numeral.size()
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            numeral.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
            NSGraphicsContext.restoreGraphicsState()
        case .highlight(let box):
            context.setFillColor(color.copy(alpha: 0.35) ?? color)
            context.fill(box)
        case .pen(let points):
            guard let first = points.first else { return }
            context.move(to: first)
            points.dropFirst().forEach { context.addLine(to: $0) }
            context.strokePath()
        case .text(let string, let point):
            let size = annotation.lineWidth * 5
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor(cgColor: color) ?? .red,
            ]
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            // The point is where the pointer was: the middle of the text's left edge.
            NSAttributedString(string: string, attributes: attributes)
                .draw(at: CGPoint(x: point.x, y: point.y - size * 0.6))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// The picture with the annotations drawn into it.
    static func render(_ image: CGImage, annotations: [Annotation]) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // From here on the origin is at the top left, as the annotations expect.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(annotations, over: image, in: context)
        return context.makeImage()
    }
}
