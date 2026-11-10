import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var model = StudioModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PreviewCard(model: model)
                    SourceButtons(pickerItem: $pickerItem, showCamera: $showCamera, hasImage: model.original != nil)
                    if model.original != nil {
                        StylePicker(model: model)
                        OptionsPanel(model: model, showSettings: $showSettings)
                        if model.result != nil {
                            ExportBar(model: model)
                        }
                    }
                }
                .padding()
                .animation(.snappy, value: model.original != nil)
                .animation(.snappy, value: model.style)
            }
            .background(
                LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.97), Color(red: 0.93, green: 0.95, blue: 1)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
            .navigationTitle("ChibiPix")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        model.setImage(image)
                    } else {
                        model.errorMessage = "Couldn't open that photo."
                    }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { model.setImage($0) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showSettings, onDismiss: { model.refreshKeyState() }) {
                SettingsView()
            }
            .alert("Oops", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation { model.toast = nil }
                        }
                }
            }
            .animation(.snappy, value: model.toast)
        }
    }
}

// MARK: - Preview

struct PreviewCard: View {
    @Bindable var model: StudioModel

    var body: some View {
        ZStack {
            Checkerboard()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if let image = model.displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(model.style == .pixel && !model.showingOriginal && model.result != nil ? .none : .high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onLongPressGesture(minimumDuration: 0.05, perform: {}, onPressingChanged: { pressing in
                        model.showingOriginal = pressing
                    })
                    .accessibilityLabel(model.result != nil ? "Stylised result" : "Original photo")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.and.background.dotted")
                        .font(.system(size: 54))
                        .foregroundStyle(.pink.gradient)
                    Text("Pick a photo of a person or pet")
                        .font(.headline)
                    Text("ChibiPix turns them into a chibi character or a pixel-art sprite.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            }

            if model.isProcessing {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    if let status = model.statusMessage {
                        Text(status).font(.footnote).multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .overlay(alignment: .topLeading) {
            if model.result != nil {
                Text(model.showingOriginal ? "Original" : "Hold to compare")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let kind = model.detectedKind, model.original != nil {
                Label(kind.label, systemImage: kind == .animal ? "pawprint.fill" : "person.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
        }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 14
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.97)))
            for row in 0...Int(size.height / cell) {
                for col in 0...Int(size.width / cell) where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(Color(white: 0.91)))
                }
            }
        }
    }
}

// MARK: - Source

struct SourceButtons: View {
    @Binding var pickerItem: PhotosPickerItem?
    @Binding var showCamera: Bool
    var hasImage: Bool

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(hasImage ? "New photo" : "Choose photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.pink)
            }
        }
        .controlSize(.large)
    }
}

// MARK: - Style

struct StylePicker: View {
    @Bindable var model: StudioModel

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ArtStyle.allCases) { style in
                let selected = model.style == style
                Button { model.style = style } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: style.symbol).font(.title2)
                        Text(style.rawValue).font(.headline)
                        Text(style.tagline).font(.caption).foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? AnyShapeStyle(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                           : AnyShapeStyle(.background))
                    )
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.05), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Export

struct ExportBar: View {
    @Bindable var model: StudioModel

    var body: some View {
        HStack(spacing: 12) {
            if let data = model.resultPNG, let image = model.result {
                ShareLink(item: PNGFile(data: data), preview: SharePreview("ChibiPix art", image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button {
                Task { await model.saveToPhotos() }
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .tint(.purple)
    }
}

struct PNGFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName("ChibiPix.png")
    }
}
