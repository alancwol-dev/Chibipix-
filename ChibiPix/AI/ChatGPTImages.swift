import UIKit

/// ChatGPT image generation (ChatGPT Images 2.6) via OpenAI's Image API edit endpoint.
/// The photo is sent as the reference image together with a chibi or pixel-art prompt.
/// Needs an OpenAI API key (platform.openai.com). A ChatGPT Plus/Pro subscription does not include API access.
struct ChatGPTImages {
    var apiKey: String
    var model: ChatGPTImageModel
    var quality: ChatGPTImageQuality

    static let modelDefaultsKey = "chatgptImageModel"
    static let customModelDefaultsKey = "chatgptCustomModel"
    static let qualityDefaultsKey = "chatgptImageQuality"

    /// Reads the user's choices from Settings.
    static func fromSettings(apiKey: String) -> ChatGPTImages {
        let defaults = UserDefaults.standard
        var model = ChatGPTImageModel(rawValue: defaults.string(forKey: modelDefaultsKey) ?? "") ?? .flare
        if model == .custom {
            let custom = defaults.string(forKey: customModelDefaultsKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            if custom.isEmpty { model = .flare }
        }
        let quality = ChatGPTImageQuality(rawValue: defaults.string(forKey: qualityDefaultsKey) ?? "") ?? .medium
        return ChatGPTImages(apiKey: apiKey, model: model, quality: quality)
    }

    private var modelID: String {
        if model == .custom {
            return UserDefaults.standard.string(forKey: Self.customModelDefaultsKey)?
                .trimmingCharacters(in: .whitespaces) ?? ChatGPTImageModel.flare.rawValue
        }
        return model.rawValue
    }

    enum ChatGPTError: LocalizedError {
        case encoding, badResponse(String), noImage
        var errorDescription: String? {
            switch self {
            case .encoding: return "Couldn't prepare the photo for upload."
            case .badResponse(let message): return "ChatGPT: \(message)"
            case .noImage: return "ChatGPT didn't return an image."
            }
        }
    }

    static func prompt(for style: ArtStyle, kind: SubjectKind) -> String {
        let subject: String
        switch kind {
        case .person: subject = "the person"
        case .animal: subject = "the animal"
        case .unknown: subject = "the main subject"
        }
        switch style {
        case .chibi:
            return """
            Redraw \(subject) in this photo as a cute Japanese chibi (super-deformed) anime character. \
            Oversized head roughly equal in height to the small, rounded body (about 2.5 heads tall), \
            large sparkling anime eyes with highlights, tiny hands and feet, soft blush on the cheeks, \
            clean bold line art, soft cel shading, bright pastel colours. Keep the recognisable features \
            of \(subject): hair or fur colour and pattern, clothing, accessories and expression. \
            Full body, centred, with a thick white sticker outline on a simple light pastel background. \
            No text.
            """
        case .pixel:
            return """
            Redraw \(subject) in this photo as a 16-bit retro video-game pixel art sprite. \
            Full body, front-facing three-quarter view, cute slightly chibi proportions, chunky readable \
            pixels, limited colour palette, dark 1-pixel outline, simple flat shading, no anti-aliasing. \
            Keep the recognisable features of \(subject): hair or fur colour and pattern, clothing and accessories. \
            Centred on a plain flat white background. No text.
            """
        }
    }

    func stylize(image: UIImage, style: ArtStyle, kind: SubjectKind) async throws -> UIImage {
        let upload = ImageUtils.normalized(image, maxDimension: 1536)
        guard let png = upload.pngData() else { throw ChatGPTError.encoding }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        let boundary = "ChibiPix-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        appendField("model", modelID)
        appendField("prompt", Self.prompt(for: style, kind: kind))
        appendField("size", "1024x1024")
        appendField("quality", quality.rawValue)
        appendField("n", "1")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"photo.png\"\r\nContent-Type: image/png\r\n\r\n")
        body.append(png)
        body.append("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(status) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "request failed (HTTP \(status))."
            throw ChatGPTError.badResponse(message)
        }
        guard let first = (json?["data"] as? [[String: Any]])?.first else { throw ChatGPTError.noImage }
        if let b64 = first["b64_json"] as? String, let bytes = Data(base64Encoded: b64), let img = UIImage(data: bytes) {
            return img
        }
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            let (bytes, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: bytes) { return img }
        }
        throw ChatGPTError.noImage
    }
}

/// The models behind ChatGPT Images 2.6 (released 4 Nov 2026).
enum ChatGPTImageModel: String, CaseIterable, Identifiable {
    case flare = "gpt-image-2.6-flare"
    case sunburst = "gpt-image-2.6-sunburst"
    case custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .flare: return "Flare (fast)"
        case .sunburst: return "Sunburst (most detailed)"
        case .custom: return "Other model…"
        }
    }
}

enum ChatGPTImageQuality: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
