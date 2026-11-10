import SwiftUI
import Photos
import Observation

@MainActor
@Observable
final class StudioModel {
    // Input / output
    private(set) var original: UIImage?
    private(set) var result: UIImage?
    private(set) var resultPNG: Data?

    // Settings — any change re-renders (debounced).
    var style: ArtStyle = .chibi { didSet { if style != oldValue { scheduleRender(debounce: false) } } }
    var engine: Engine = .onDevice { didSet { if engine != oldValue { scheduleRender(debounce: false) } } }
    var chibi = ChibiOptions() { didSet { if chibi != oldValue { scheduleRender(debounce: true) } } }
    var pixel = PixelOptions() { didSet { if pixel != oldValue { scheduleRender(debounce: true) } } }

    // UI state
    private(set) var isProcessing = false
    private(set) var statusMessage: String?
    private(set) var detectedKind: SubjectKind?
    private(set) var hasSegmentation = true
    private(set) var hasAPIKey = KeychainStore.hasKey
    var showingOriginal = false
    var errorMessage: String?
    var toast: String?

    var displayedImage: UIImage? {
        showingOriginal ? original : (result ?? original)
    }

    var needsAIGeneration: Bool { engine == .ai && aiBase[style] == nil }

    // Caches
    @ObservationIgnored private var sourceCG: CGImage?
    @ObservationIgnored private var analysis: SubjectAnalysis?
    @ObservationIgnored private var aiBase: [ArtStyle: (image: CGImage, analysis: SubjectAnalysis?)] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    // MARK: - Input

    func setImage(_ image: UIImage) {
        task?.cancel()
        let normalized = ImageUtils.normalized(image, maxDimension: 1024)
        original = normalized
        sourceCG = normalized.cgImage
        analysis = nil
        aiBase = [:]
        detectedKind = nil
        showingOriginal = false
        setResult(nil)
        scheduleRender(debounce: false)
    }

    func refreshKeyState() {
        hasAPIKey = KeychainStore.hasKey
    }

    // MARK: - Rendering

    private struct Output {
        var image: CGImage?
        var analysis: SubjectAnalysis?
        var aiAnalysis: SubjectAnalysis?
    }

    private func scheduleRender(debounce: Bool) {
        guard let source = sourceCG else { return }
        task?.cancel()

        let style = style, engine = engine, chibi = chibi, pixel = pixel
        let cached = analysis
        let base = aiBase[style]

        if engine == .ai && base == nil {
            // Wait for the user to tap "Generate" — AI calls cost money.
            setResult(nil)
            isProcessing = false
            statusMessage = nil
            if cached == nil { analyzeOnly(source) }
            return
        }

        isProcessing = true
        statusMessage = cached == nil ? "Finding the subject…" : nil

        task = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(180)) }
            if Task.isCancelled { return }

            let output = await Task.detached(priority: .userInitiated) { () -> Output in
                switch (engine, style) {
                case (.onDevice, .chibi):
                    let a = cached ?? SubjectAnalyzer.analyze(source)
                    return Output(image: ChibiRenderer.render(image: source, analysis: a, options: chibi), analysis: a)
                case (.onDevice, .pixel):
                    let a = cached ?? SubjectAnalyzer.analyze(source)
                    return Output(image: PixelArtRenderer.render(image: source, analysis: a, options: pixel), analysis: a)
                case (.ai, .chibi):
                    return Output(image: base?.image)
                case (.ai, .pixel):
                    guard let base else { return Output() }
                    let a = base.analysis ?? SubjectAnalyzer.analyze(base.image)
                    return Output(image: PixelArtRenderer.render(image: base.image, analysis: a, options: pixel), aiAnalysis: a)
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            if let a = output.analysis { self.store(analysis: a) }
            if let a = output.aiAnalysis, let base = self.aiBase[style] {
                self.aiBase[style] = (base.image, a)
            }
            self.isProcessing = false
            self.statusMessage = nil
            if let image = output.image {
                self.setResult(image)
            } else {
                self.setResult(nil)
                self.errorMessage = "Couldn't find a person or animal in this photo. Try one where the subject is clearly visible."
            }
        }
    }

    private func analyzeOnly(_ source: CGImage) {
        Task { [weak self] in
            let a = await Task.detached(priority: .utility) { SubjectAnalyzer.analyze(source) }.value
            guard let self, self.sourceCG === source, self.analysis == nil else { return }
            self.store(analysis: a)
        }
    }

    private func store(analysis a: SubjectAnalysis) {
        analysis = a
        detectedKind = a.kind
        hasSegmentation = a.mask != nil
    }

    private func setResult(_ image: CGImage?) {
        guard let image else {
            result = nil
            resultPNG = nil
            return
        }
        let ui = UIImage(cgImage: image)
        result = ui
        resultPNG = ui.pngData()
    }

    // MARK: - AI

    func generateAI() {
        guard let original else { return }
        guard let key = KeychainStore.load(), !key.isEmpty else {
            errorMessage = "Add your OpenAI API key in Settings to use ChatGPT image generation."
            return
        }
        task?.cancel()
        isProcessing = true
        statusMessage = "ChatGPT is drawing… this can take up to a minute"
        let style = style
        let kind = analysis?.kind ?? .unknown
        let stylizer = ChatGPTImages.fromSettings(apiKey: key)

        task = Task { [weak self] in
            do {
                let image = try await stylizer.stylize(image: original, style: style, kind: kind)
                guard let self, !Task.isCancelled else { return }
                guard let cg = ImageUtils.normalized(image, maxDimension: 1024).cgImage else {
                    throw ChatGPTImages.ChatGPTError.noImage
                }
                self.aiBase[style] = (cg, nil)
                self.scheduleRender(debounce: false)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isProcessing = false
                self.statusMessage = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Export

    func saveToPhotos() async {
        guard let data = resultPNG else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            errorMessage = "ChibiPix needs permission to add photos. You can allow it in Settings › Privacy › Photos."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            toast = "Saved to Photos"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
