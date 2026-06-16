import AppKit
import Vision

enum AIPackGeneratorError: LocalizedError {
    case aiNotConfigured
    case missingAPIKey
    case networkError(underlying: Error)
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case decodingFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .aiNotConfigured:
            return "AI model is not configured."
        case .missingAPIKey:
            return "API key is missing."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from image API."
        case .decodingFailed:
            return "Could not decode generated image."
        case .cancelled:
            return "Generation was cancelled."
        }
    }
}

final class AIPackGenerator: PetAssetGenerating {
    private struct PoseRequest {
        let fileName: String
        let poseInstruction: String
    }

    private static let staticPoses: [PoseRequest] = [
        PoseRequest(fileName: "sit.png",
                    poseInstruction: "sitting upright on its haunches, front legs straight, back straight, alert expression, facing slightly toward the viewer, side-front 3/4 angle"),
        PoseRequest(fileName: "loaf.png",
                    poseInstruction: "in a cat-loaf pose — body resting flat on the ground, all four paws completely tucked under the body, round compact silhouette, side view, eyes open and content"),
        PoseRequest(fileName: "sleep.png",
                    poseInstruction: "sleeping — curled up in a ball with tail wrapped around its body, eyes fully closed and relaxed, side view")
    ]

    private static let walkPoses: [PoseRequest] = [
        PoseRequest(fileName: "walk_01.png",
                    poseInstruction: "mid-walk stride phase 1 — side view, left front leg reaching forward, right hind leg pushing back, body moving left-to-right"),
        PoseRequest(fileName: "walk_02.png",
                    poseInstruction: "mid-walk stride phase 2 — side view, left front leg on the ground bearing weight, right front leg lifting, body moving left-to-right"),
        PoseRequest(fileName: "walk_03.png",
                    poseInstruction: "mid-walk stride phase 3 — side view, legs passing under body, compact gathered stance mid-stride, body moving left-to-right"),
        PoseRequest(fileName: "walk_04.png",
                    poseInstruction: "mid-walk stride phase 4 — side view, right front leg reaching forward, left hind leg pushing back, body moving left-to-right"),
        PoseRequest(fileName: "walk_05.png",
                    poseInstruction: "mid-walk stride phase 5 — side view, right front leg on the ground bearing weight, left front leg lifting, body moving left-to-right"),
        PoseRequest(fileName: "walk_06.png",
                    poseInstruction: "mid-walk stride phase 6 — side view, legs passing under body again, returning to phase 1, body moving left-to-right")
    ]

    private let settings: AIModelSettings
    private let apiKey: String
    private let petName: String
    private let style: String
    private let notes: String
    private let allImageURLs: [URL]

    private var usesChatAPI: Bool {
        settings.endpoint.contains("chat/completions")
    }

    var onProgress: ((String) -> Void)?
    var isCancelled: (() -> Bool)?

    init(settings: AIModelSettings, apiKey: String, petName: String, style: String, notes: String, imageURLs: [URL]) {
        self.settings = settings
        self.apiKey = apiKey
        self.petName = petName
        self.style = style
        self.notes = notes
        self.allImageURLs = imageURLs
    }

    func generatePetPack(from imageURL: URL, rootURL: URL) throws -> GeneratedPetPack {
        let referenceImages = try prepareReferenceImages()
        guard !referenceImages.isEmpty else {
            throw PetPackGeneratorError.cannotLoadImage
        }

        let packName = PetPackGenerator.uniquePackName(baseName: imageURL.deletingPathExtension().lastPathComponent, rootURL: rootURL)
        let packDirectory = rootURL.appendingPathComponent(packName, isDirectory: true)
        try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)

        let allPoses: [PoseRequest] = Self.staticPoses + Self.walkPoses
        let total = allPoses.count + 1

        if isCancelled?() == true { throw AIPackGeneratorError.cancelled }
        onProgress?(L("AI 生成中 1/\(total)（待机）...", "AI generating 1/\(total) (idle)..."))
        let reclinePrompt = promptForRecline()
        let reclineData = try callAPI(referenceImages: referenceImages, prompt: reclinePrompt)
        let reclineImage = try placeOnCanvas(reclineData)
        try PetPackGenerator.writePNG(reclineImage, to: packDirectory.appendingPathComponent("recline.png"))

        Thread.sleep(forTimeInterval: 1.0)

        for (index, pose) in allPoses.enumerated() {
            if isCancelled?() == true { throw AIPackGeneratorError.cancelled }

            let step = index + 2
            onProgress?(L("AI 生成中 \(step)/\(total)...", "AI generating \(step)/\(total)..."))

            let prompt = promptForPose(pose)
            let responseData = try callAPI(referenceImages: referenceImages, prompt: prompt)
            let generated = try placeOnCanvas(responseData)
            try PetPackGenerator.writePNG(generated, to: packDirectory.appendingPathComponent(pose.fileName))

            if step < total {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }

        let manifest = """
        {
          "schema": 1,
          "name": "\(PetPackGenerator.jsonEscape(packName))",
          "source": "\(PetPackGenerator.jsonEscape(imageURL.lastPathComponent))",
          "generator": "ai-api-v2",
          "api_mode": "\(usesChatAPI ? "chat" : "edits")",
          "reference_count": \(referenceImages.count),
          "notes": "All 10 poses generated via AI from \(referenceImages.count) reference image(s)."
        }
        """
        try manifest.write(to: packDirectory.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)

        return GeneratedPetPack(name: packName, directory: packDirectory)
    }

    // MARK: - Reference image preparation

    private func prepareReferenceImages() throws -> [(data: Data, fileName: String)] {
        var results: [(data: Data, fileName: String)] = []
        for (index, url) in allImageURLs.prefix(3).enumerated() {
            guard let source = NSImage(contentsOf: url),
                  let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }
            let prepared = PetPackGenerator.foregroundSegmentedImage(from: cgImage) ?? cgImage
            let trimmed = (try? PetPackGenerator.trimmedImage(from: prepared)) ?? prepared
            let resized = Self.resizeIfNeeded(trimmed, maxDimension: 768)
            let rep = NSBitmapImageRep(cgImage: resized)
            guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { continue }
            debugLog("ref image \(index + 1): \(resized.width)x\(resized.height), \(jpegData.count / 1024)KB")
            results.append((data: jpegData, fileName: "ref_\(index + 1).jpg"))
        }
        return results
    }

    private static func resizeIfNeeded(_ image: CGImage, maxDimension: Int) -> CGImage {
        let w = image.width
        let h = image.height
        guard w > maxDimension || h > maxDimension else { return image }
        let scale = CGFloat(maxDimension) / CGFloat(max(w, h))
        let newW = Int(CGFloat(w) * scale)
        let newH = Int(CGFloat(h) * scale)
        guard let context = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: newW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage() ?? image
    }

    // MARK: - Prompt building

    private var imageRefText: String {
        let count = min(allImageURLs.count, 8)
        if count <= 1 { return "the reference image" }
        return "the \(count) reference images"
    }

    private func promptForRecline() -> String {
        let name = petName.isEmpty ? "this pet" : petName
        return """
        Using \(imageRefText) ONLY as identity reference for \(name)'s appearance (fur color, markings, body shape, face), \
        generate a COMPLETELY NEW image of the SAME animal in this SPECIFIC pose: \
        relaxed side-lying recline, body stretched out, legs visible and relaxed, calm idle expression, side view. \
        Style: \(style). \(notes) \
        CRITICAL: You MUST change the pose to match the description above. Do NOT reproduce the pose from the reference image. \
        The reference shows what the animal looks like, NOT how it should be posed. \
        Single subject only, transparent background, no text, no extra objects, centered in frame.
        """
    }

    private func promptForPose(_ pose: PoseRequest) -> String {
        let name = petName.isEmpty ? "this pet" : petName
        return """
        Using \(imageRefText) ONLY as identity reference for \(name)'s appearance (fur color, markings, body shape, face), \
        generate a COMPLETELY NEW image of the SAME animal in this SPECIFIC pose: \
        \(pose.poseInstruction). \
        Style: \(style). \(notes) \
        CRITICAL: You MUST change the pose to match the description above. Do NOT reproduce the pose from the reference image. \
        The reference shows what the animal looks like, NOT how it should be posed. \
        Single subject only, transparent background, no text, no extra objects, centered in frame.
        """
    }

    // MARK: - API dispatch

    private func callAPI(referenceImages: [(data: Data, fileName: String)], prompt: String) throws -> Data {
        if usesChatAPI {
            return try executeChatAPICall(referenceImages: referenceImages, prompt: prompt)
        } else {
            return try executeEditsAPICall(referenceImages: referenceImages, prompt: prompt)
        }
    }

    // MARK: - Chat completions API (Gemini, etc.)

    private func executeChatAPICall(referenceImages: [(data: Data, fileName: String)], prompt: String) throws -> Data {
        guard let url = URL(string: settings.endpoint) else {
            throw AIPackGeneratorError.aiNotConfigured
        }

        var contentParts: [[String: Any]] = []
        for ref in referenceImages {
            let b64 = ref.data.base64EncodedString()
            let mime = ref.fileName.hasSuffix(".jpg") ? "image/jpeg" : "image/png"
            contentParts.append([
                "type": "image_url",
                "image_url": ["url": "data:\(mime);base64,\(b64)"]
            ])
        }
        contentParts.append([
            "type": "text",
            "text": prompt
        ])

        let payload: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "user", "content": contentParts]
            ],
            "max_tokens": 4096
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw AIPackGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = jsonData

        debugLog("AI chat API call: \(url.absoluteString) model=\(settings.model) refs=\(referenceImages.count)")

        let (data, status) = try synchronousRequest(request)

        if status != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("AI chat API error \(status): \(String(message.prefix(300)))")
            throw AIPackGeneratorError.apiError(statusCode: status, message: String(message.prefix(500)))
        }

        return try parseChatImageResponse(data)
    }

    private func parseChatImageResponse(_ data: Data) throws -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIPackGeneratorError.invalidResponse
        }

        let content = message["content"]

        if let contentArray = content as? [[String: Any]] {
            for item in contentArray {
                if let imageData = extractImageData(from: item) { return imageData }
            }
        }

        if let contentStr = content as? String {
            if let imageData = extractBase64FromMarkdown(contentStr) { return imageData }
        }

        throw AIPackGeneratorError.decodingFailed
    }

    private func extractImageData(from item: [String: Any]) -> Data? {
        guard let type = item["type"] as? String else { return nil }
        if type == "image_url",
           let imageURL = item["image_url"] as? [String: Any],
           let urlStr = imageURL["url"] as? String {
            return decodeDataURL(urlStr)
        }
        if type == "image",
           let b64 = item["data"] as? String {
            return Data(base64Encoded: b64)
        }
        return nil
    }

    private func extractBase64FromMarkdown(_ text: String) -> Data? {
        guard let range = text.range(of: "data:image/png;base64,") ??
                          text.range(of: "data:image/jpeg;base64,") ??
                          text.range(of: "data:image/webp;base64,") else {
            return nil
        }
        let afterPrefix = text[range.upperBound...]
        let b64End = afterPrefix.firstIndex(where: { $0 == ")" || $0 == "\"" || $0 == " " || $0 == "\n" }) ?? afterPrefix.endIndex
        let b64 = String(afterPrefix[..<b64End])
        return Data(base64Encoded: b64)
    }

    private func decodeDataURL(_ urlStr: String) -> Data? {
        guard let commaIndex = urlStr.firstIndex(of: ",") else { return nil }
        let b64 = String(urlStr[urlStr.index(after: commaIndex)...])
        return Data(base64Encoded: b64)
    }

    // MARK: - Images/edits API (GPT-image, DALL-E)

    private func executeEditsAPICall(referenceImages: [(data: Data, fileName: String)], prompt: String) throws -> Data {
        guard let url = URL(string: settings.endpoint) else {
            throw AIPackGeneratorError.aiNotConfigured
        }

        let boundary = "SkillsPet-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = buildMultipartBody(referenceImages: referenceImages, prompt: prompt, boundary: boundary)

        debugLog("AI edits API call: \(url.absoluteString) model=\(settings.model) refs=\(referenceImages.count)")

        let (data, status) = try synchronousRequest(request)

        if status != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("AI edits API error \(status): \(String(message.prefix(300)))")
            throw AIPackGeneratorError.apiError(statusCode: status, message: String(message.prefix(500)))
        }

        return try parseEditsImageResponse(data)
    }

    private func buildMultipartBody(referenceImages: [(data: Data, fileName: String)], prompt: String, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"

        func appendField(name: String, value: String) {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".utf8))
            body.append(Data("\(value)\(crlf)".utf8))
        }

        func appendFile(name: String, fileName: String, mimeType: String, data: Data) {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\(crlf)".utf8))
            body.append(Data("Content-Type: \(mimeType)\(crlf)\(crlf)".utf8))
            body.append(data)
            body.append(Data(crlf.utf8))
        }

        for ref in referenceImages {
            appendFile(name: "image[]", fileName: ref.fileName, mimeType: "image/png", data: ref.data)
        }
        appendField(name: "prompt", value: prompt)
        appendField(name: "model", value: settings.model)
        appendField(name: "background", value: "transparent")
        appendField(name: "quality", value: apiQuality)
        appendField(name: "size", value: "1024x1024")
        appendField(name: "output_format", value: "png")
        appendField(name: "n", value: "1")

        body.append(Data("--\(boundary)--\(crlf)".utf8))
        return body
    }

    private func parseEditsImageResponse(_ data: Data) throws -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first else {
            throw AIPackGeneratorError.invalidResponse
        }

        if let b64 = first["b64_json"] as? String,
           let decoded = Data(base64Encoded: b64) {
            return decoded
        }

        if let urlString = first["url"] as? String,
           let url = URL(string: urlString),
           let downloaded = try? Data(contentsOf: url) {
            return downloaded
        }

        throw AIPackGeneratorError.decodingFailed
    }

    private var apiQuality: String {
        switch settings.qualityMode {
        case .cheap: return "low"
        case .standard: return "medium"
        case .high: return "high"
        }
    }

    // MARK: - Shared HTTP

    private func synchronousRequest(_ request: URLRequest) throws -> (Data, Int) {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var httpResponse: HTTPURLResponse?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            httpResponse = response as? HTTPURLResponse
            semaphore.signal()
        }
        task.resume()
        let waitResult = semaphore.wait(timeout: .now() + 180)

        if waitResult == .timedOut {
            task.cancel()
            throw AIPackGeneratorError.networkError(underlying: URLError(.timedOut))
        }

        if let error = responseError {
            throw AIPackGeneratorError.networkError(underlying: error)
        }

        guard let data = responseData, let status = httpResponse?.statusCode else {
            throw AIPackGeneratorError.invalidResponse
        }

        return (data, status)
    }

    // MARK: - Canvas placement

    private func placeOnCanvas(_ imageData: Data) throws -> CGImage {
        guard let nsImage = NSImage(data: imageData),
              let source = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AIPackGeneratorError.decodingFailed
        }

        let canvas = PetPackGenerator.targetCanvas
        let width = Int(canvas.width)
        let height = Int(canvas.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PetPackGeneratorError.cannotRenderImage
        }

        context.clear(CGRect(origin: .zero, size: canvas))
        context.interpolationQuality = .high

        let maxDrawWidth = canvas.width * 0.72
        let maxDrawHeight = canvas.height * 0.74
        let sourceSize = CGSize(width: source.width, height: source.height)
        let scale = min(maxDrawWidth / sourceSize.width, maxDrawHeight / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = CGRect(
            x: (canvas.width - drawSize.width) / 2,
            y: (canvas.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.draw(source, in: drawRect)

        guard let result = context.makeImage() else {
            throw PetPackGeneratorError.cannotRenderImage
        }
        return result
    }
}
