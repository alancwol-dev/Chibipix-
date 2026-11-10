import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Turn on Apple Intelligence in the Settings app.", systemImage: "1.circle")
                    Label("Go to Settings › Apple Intelligence & Siri › ChatGPT and turn on the extension. You can use it without an account, or sign in to a free or paid ChatGPT account for higher limits.", systemImage: "2.circle")
                    Label("In ChibiPix, choose the ChatGPT (free) engine and tap Generate. Pick the ChatGPT style in the sheet if needed.", systemImage: "3.circle")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Free ChatGPT image generation")
                } footer: {
                    Text("ChibiPix uses Apple's Image Playground with its ChatGPT style. It costs nothing and needs no API key, but ChatGPT's free-plan daily image limits apply. Requires iOS 26 or later on an Apple Intelligence iPhone or iPad. Your photo is shared with ChatGPT only when you generate.")
                }
                .font(.footnote)

                Section("How it works") {
                    Label("Vision lifts the person or pet out of the photo and finds the face and eyes.", systemImage: "viewfinder")
                    Label("Chibi: the head is enlarged, the body shortened, the eyes widened, then cel-shaded and inked.", systemImage: "sparkles")
                    Label("Pixel art: the subject is sampled onto a real pixel grid and mapped to a retro palette.", systemImage: "square.grid.3x3.fill")
                    Label("On-device mode never uploads anything.", systemImage: "lock.shield")
                }
                .font(.footnote)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
