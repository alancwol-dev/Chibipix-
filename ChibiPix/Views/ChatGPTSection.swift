import SwiftUI
import ImagePlayground

/// Free ChatGPT image generation through Apple's Image Playground.
/// Image Playground's "ChatGPT" style (`.externalProvider`) uses the ChatGPT account the person
/// set up in Settings › Apple Intelligence & Siri › ChatGPT — the free ChatGPT tier works, and
/// no API key or payment is involved. Requires iOS 26+ on an Apple Intelligence device.
struct ChatGPTSection: View {
    @Bindable var model: StudioModel

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            ChatGPTPlaygroundButton(model: model)
        } else {
            ChatGPTUnavailableNote(text: "ChatGPT image generation needs iOS 26 or later on an iPhone or iPad with Apple Intelligence.")
        }
        #else
        ChatGPTUnavailableNote(text: "This build was made with an older Xcode. Rebuild with Xcode 26 or later to enable ChatGPT.")
        #endif
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private struct ChatGPTPlaygroundButton: View {
    @Bindable var model: StudioModel
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var showingPlayground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.style == .chibi
                 ? "ChatGPT redraws your photo as a hand-drawn chibi character."
                 : "ChatGPT draws a sprite, then ChibiPix snaps it to a true pixel grid using the settings below.")
                .font(.subheadline)
            Label("Free — uses your ChatGPT account from iPhone Settings (free plan works, with ChatGPT's daily limits). Pick the ChatGPT style in the sheet if it isn't already selected.",
                  systemImage: "checkmark.seal")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button { showingPlayground = true } label: {
                Label(model.needsAIGeneration ? "Generate with ChatGPT" : "Regenerate", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.purple)
            .disabled(!supportsImagePlayground || model.isProcessing || model.original == nil)

            if !supportsImagePlayground {
                Label("Turn on Apple Intelligence in Settings, then connect ChatGPT under Settings › Apple Intelligence & Siri › ChatGPT. Needs an Apple Intelligence iPhone or iPad (iPhone 15 Pro or newer).",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .imagePlaygroundSheet(
            isPresented: $showingPlayground,
            concepts: [.text(model.playgroundPrompt)],
            sourceImage: model.original.map { Image(uiImage: $0) },
            onCompletion: { url in
                model.receivePlaygroundImage(at: url)
            }
        )
        .imagePlaygroundGenerationStyle(.externalProvider,
                                        in: [.externalProvider, .animation, .illustration, .sketch])
    }
}
#endif

private struct ChatGPTUnavailableNote: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.orange)
    }
}
