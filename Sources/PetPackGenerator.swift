import AppKit
import Vision

struct GeneratedPetPack {
    let name: String
    let directory: URL
}

protocol PetAssetGenerating {
    func generatePetPack(from imageURL: URL, rootURL: URL) throws -> GeneratedPetPack
}

enum PetPackGeneratorError: LocalizedError {
    case cannotLoadImage
    case cannotRenderImage
    case cannotCreatePNG

    var errorDescription: String? {
        switch self {
        case .cannotLoadImage:
            return "Could not load the selected image."
        case .cannotRenderImage:
            return "Could not render the selected image."
        case .cannotCreatePNG:
            return "Could not create PNG files for the pet pack."
        }
    }
}

final class PetPackGenerator: PetAssetGenerating {
    private struct Variant {
        let fileName: String
        let scaleX: CGFloat
        let scaleY: CGFloat
        let rotation: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    private let fileManager = FileManager.default
    private let targetCanvas = CGSize(width: 512, height: 384)

    func generatePetPack(from imageURL: URL, rootURL: URL) throws -> GeneratedPetPack {
        guard let source = NSImage(contentsOf: imageURL),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PetPackGeneratorError.cannotLoadImage
        }

        let prepared = foregroundSegmentedImage(from: cgImage) ?? cgImage
        let trimmed = try trimmedImage(from: prepared)
        let packName = uniquePackName(baseName: imageURL.deletingPathExtension().lastPathComponent, rootURL: rootURL)
        let packDirectory = rootURL.appendingPathComponent(packName, isDirectory: true)
        try fileManager.createDirectory(at: packDirectory, withIntermediateDirectories: true)

        for variant in variants() {
            let image = try renderVariant(trimmed, variant: variant)
            try writePNG(image, to: packDirectory.appendingPathComponent(variant.fileName))
        }

        let manifest = """
        {
          "schema": 1,
          "name": "\(jsonEscape(packName))",
          "source": "\(jsonEscape(imageURL.lastPathComponent))",
          "generator": "local-procedural-v1",
          "notes": "Generated from one image. Motions are procedural; model-generated poses can replace these files later."
        }
        """
        try manifest.write(to: packDirectory.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)

        return GeneratedPetPack(name: packName, directory: packDirectory)
    }

    private func variants() -> [Variant] {
        [
            Variant(fileName: "recline.png", scaleX: 1.00, scaleY: 1.00, rotation: 0.00, offsetX: 0, offsetY: 0),
            Variant(fileName: "loaf.png", scaleX: 1.16, scaleY: 0.78, rotation: 0.00, offsetX: 0, offsetY: -36),
            Variant(fileName: "sit.png", scaleX: 0.88, scaleY: 1.14, rotation: 0.00, offsetX: 0, offsetY: 18),
            Variant(fileName: "sleep.png", scaleX: 1.28, scaleY: 0.54, rotation: -0.045, offsetX: 0, offsetY: -72),
            Variant(fileName: "walk_01.png", scaleX: 1.04, scaleY: 0.94, rotation: -0.070, offsetX: -28, offsetY: -6),
            Variant(fileName: "walk_02.png", scaleX: 0.94, scaleY: 1.10, rotation: 0.040, offsetX: -16, offsetY: 18),
            Variant(fileName: "walk_03.png", scaleX: 1.06, scaleY: 0.92, rotation: 0.075, offsetX: 0, offsetY: 0),
            Variant(fileName: "walk_04.png", scaleX: 0.93, scaleY: 1.12, rotation: -0.035, offsetX: 16, offsetY: 20),
            Variant(fileName: "walk_05.png", scaleX: 1.04, scaleY: 0.94, rotation: -0.080, offsetX: 28, offsetY: -4),
            Variant(fileName: "walk_06.png", scaleX: 0.96, scaleY: 1.08, rotation: 0.050, offsetX: 10, offsetY: 16)
        ]
    }

    private func foregroundSegmentedImage(from image: CGImage) -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                debugLog("Vision foreground mask produced no observation")
                return nil
            }

            let maskedBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let segmented = context.createCGImage(ciImage, from: ciImage.extent) else {
                debugLog("Vision foreground mask could not create CGImage")
                return nil
            }
            debugLog("Vision foreground mask applied")
            return segmented
        } catch {
            debugLog("Vision foreground mask failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func trimmedImage(from image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PetPackGeneratorError.cannotRenderImage
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            throw PetPackGeneratorError.cannotRenderImage
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        let hasTransparency = (0 ..< width * height).contains { pixelIndex in
            pixels[pixelIndex * bytesPerPixel + 3] < 250
        }
        let edgeBackground = hasTransparency ? Set<Int>() : edgeConnectedWhiteBackground(in: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * bytesPerRow) + (x * bytesPerPixel)
                let alpha = Int(pixels[index + 3])
                let isBackground = edgeBackground.contains(y * width + x)

                if alpha > 20 && !isBackground {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                } else if isBackground {
                    pixels[index + 3] = 0
                }
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return image
        }

        let padding = max(8, min(width, height) / 60)
        let cropX = max(0, minX - padding)
        let cropY = max(0, minY - padding)
        let cropMaxX = min(width - 1, maxX + padding)
        let cropMaxY = min(height - 1, maxY + padding)
        let cropRect = CGRect(x: cropX, y: cropY, width: cropMaxX - cropX + 1, height: cropMaxY - cropY + 1)

        return context.makeImage()?.cropping(to: cropRect) ?? image
    }

    private func edgeConnectedWhiteBackground(in pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> Set<Int> {
        var visited = Array(repeating: false, count: width * height)
        var background = Set<Int>()
        var queue: [Int] = []

        func enqueueIfWhite(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let pixelID = y * width + x
            guard !visited[pixelID] else { return }
            visited[pixelID] = true

            let index = y * bytesPerRow + x * 4
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let maxChannel = max(red, max(green, blue))
            let minChannel = min(red, min(green, blue))
            let nearWhite = maxChannel > 238 && (maxChannel - minChannel) < 14
            guard nearWhite else { return }

            background.insert(pixelID)
            queue.append(pixelID)
        }

        for x in 0 ..< width {
            enqueueIfWhite(x, 0)
            enqueueIfWhite(x, height - 1)
        }
        for y in 0 ..< height {
            enqueueIfWhite(0, y)
            enqueueIfWhite(width - 1, y)
        }

        var cursor = 0
        while cursor < queue.count {
            let pixelID = queue[cursor]
            cursor += 1
            let x = pixelID % width
            let y = pixelID / width
            enqueueIfWhite(x + 1, y)
            enqueueIfWhite(x - 1, y)
            enqueueIfWhite(x, y + 1)
            enqueueIfWhite(x, y - 1)
        }

        return background
    }

    private func renderVariant(_ source: CGImage, variant: Variant) throws -> CGImage {
        let width = Int(targetCanvas.width)
        let height = Int(targetCanvas.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PetPackGeneratorError.cannotRenderImage
        }

        context.clear(CGRect(origin: .zero, size: targetCanvas))
        context.interpolationQuality = .high

        let maxDrawWidth = targetCanvas.width * 0.72
        let maxDrawHeight = targetCanvas.height * 0.74
        let sourceSize = CGSize(width: source.width, height: source.height)
        let baseScale = min(maxDrawWidth / sourceSize.width, maxDrawHeight / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * baseScale, height: sourceSize.height * baseScale)

        context.saveGState()
        context.translateBy(x: targetCanvas.width / 2 + variant.offsetX, y: targetCanvas.height * 0.48 + variant.offsetY)
        context.rotate(by: variant.rotation)
        context.scaleBy(x: variant.scaleX, y: variant.scaleY)
        let drawRect = CGRect(x: -drawSize.width / 2, y: -drawSize.height / 2, width: drawSize.width, height: drawSize.height)
        context.draw(source, in: drawRect)
        context.restoreGState()

        guard let rendered = context.makeImage() else {
            throw PetPackGeneratorError.cannotRenderImage
        }
        return rendered
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw PetPackGeneratorError.cannotCreatePNG
        }
        try data.write(to: url, options: .atomic)
    }

    private func uniquePackName(baseName: String, rootURL: URL) -> String {
        let cleanBase = sanitizedPackName(baseName).isEmpty ? "custom-pet" : sanitizedPackName(baseName)
        var candidate = cleanBase
        var suffix = 2
        while fileManager.fileExists(atPath: rootURL.appendingPathComponent(candidate, isDirectory: true).path) {
            candidate = "\(cleanBase)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func sanitizedPackName(_ value: String) -> String {
        let lowercased = value.lowercased()
        let mapped = lowercased.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        return String(mapped)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func jsonEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
