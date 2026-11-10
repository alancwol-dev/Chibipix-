import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = KeychainStore.load() ?? ""
    @AppStorage(ChatGPTImages.modelDefaultsKey) private var model: ChatGPTImageModel = .flare
    @AppStorage(ChatGPTImages.customModelDefaultsKey) private var customModel = ""
    @AppStorage(ChatGPTImages.qualityDefaultsKey) private var quality: ChatGPTImageQuality = .medium

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("OpenAI API key (sk-…)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.footnote)
                } header: {
                    Text("ChatGPT image generation")
                } footer: {
                    Text("Uses the model behind ChatGPT Images 2.6 through OpenAI's API. API usage is billed separately from a ChatGPT Plus or Pro subscription. Your key stays in this device's Keychain.")
                }

                Section {
                    Picker("Model", selection: $model) {
                        ForEach(ChatGPTImageModel.allCases) { Text($0.title).tag($0) }
                    }
                    if model == .custom {
                        TextField("Model ID, e.g. gpt-image-2.6-sunburst", text: $customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Picker("Quality", selection: $quality) {
                        ForEach(ChatGPTImageQuality.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Flare is quicker and cheaper. Sunburst keeps more of the original likeness and detail. Higher quality looks better but takes longer and costs more.")
                }

                Section("How it works") {
                    Label("Vision lifts the person or pet out of the photo and finds the face and eyes.", systemImage: "viewfinder")
                    Label("Chibi: the head is enlarged, the body shortened, the eyes widened, then cel-shaded and inked.", systemImage: "sparkles")
                    Label("Pixel art: the subject is sampled onto a real pixel grid and mapped to a retro palette.", systemImage: "square.grid.3x3.fill")
                    Label("On-device mode never uploads anything. Only the ChatGPT engine sends your photo to OpenAI.", systemImage: "lock.shield")
                }
                .font(.footnote)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        KeychainStore.save(apiKey)
                        dismiss()
                    }
                }
            }
        }
    }
}
