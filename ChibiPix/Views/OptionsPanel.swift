import SwiftUI

struct OptionsPanel: View {
    @Bindable var model: StudioModel
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Engine", selection: $model.engine) {
                ForEach(Engine.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.engine == .ai {
                ChatGPTSection(model: model)
            } else if !model.hasSegmentation {
                Label("Background removal isn't available here (it needs a real iPhone or iPad), so the whole photo is used.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            switch model.style {
            case .chibi:
                if model.engine == .onDevice { chibiControls }
            case .pixel:
                pixelControls
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    // MARK: Chibi

    private var chibiControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledSlider(title: "Head size", value: $model.chibi.headScale, range: 1.0...2.0,
                          format: { String(format: "×%.2f", $0) })
            LabeledSlider(title: "Height", value: $model.chibi.headsTall, range: 2.0...3.5,
                          format: { String(format: "%.1f heads", $0) })
            LabeledSlider(title: "Big eyes", value: $model.chibi.eyeSize, range: 0...1,
                          format: { "\(Int($0 * 100))%" })

            Toggle("Ink lines", isOn: $model.chibi.inkLines)
            Toggle("Rosy cheeks", isOn: $model.chibi.blush)
            Toggle("Eye sparkles", isOn: $model.chibi.catchlights)
            Toggle("Sticker outline", isOn: $model.chibi.sticker)

            BackdropPicker(selection: $model.chibi.backdrop)
        }
        .tint(.pink)
    }

    // MARK: Pixel

    private var pixelControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution").font(.subheadline.weight(.medium))
                Picker("Resolution", selection: $model.pixel.gridSize) {
                    ForEach(PixelOptions.gridSizes, id: \.self) { Text("\($0)px").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("Palette").font(.subheadline.weight(.medium))
                Spacer()
                Picker("Palette", selection: $model.pixel.palette) {
                    ForEach(PixelPalette.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            if model.pixel.palette == .auto {
                Stepper("Colours: \(model.pixel.colorCount)", value: $model.pixel.colorCount, in: 2...32)
            } else if let colors = model.pixel.palette.colors {
                HStack(spacing: 3) {
                    ForEach(colors.indices, id: \.self) { i in
                        Rectangle()
                            .fill(Color(red: Double(colors[i].x), green: Double(colors[i].y), blue: Double(colors[i].z)))
                            .frame(height: 16)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Toggle("Remove background", isOn: $model.pixel.removeBackground)
            Toggle("Sprite outline", isOn: $model.pixel.outline)
                .disabled(!model.pixel.removeBackground)
            Toggle("Retro dithering", isOn: $model.pixel.dithering)

            if model.pixel.removeBackground {
                BackdropPicker(selection: $model.pixel.backdrop)
            }
        }
        .tint(.purple)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(format(value)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
        }
    }
}

struct BackdropPicker: View {
    @Binding var selection: Backdrop

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background").font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                ForEach(Backdrop.allCases) { backdrop in
                    Button { selection = backdrop } label: {
                        ZStack {
                            if backdrop == .transparent {
                                Checkerboard().clipShape(Circle())
                            } else {
                                Circle().fill(backdrop.swatch)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(selection == backdrop ? Color.primary : Color.black.opacity(0.1),
                                                       lineWidth: selection == backdrop ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(backdrop.rawValue.capitalized)
                    .accessibilityAddTraits(selection == backdrop ? .isSelected : [])
                }
            }
        }
    }
}
