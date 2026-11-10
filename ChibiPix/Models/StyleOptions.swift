import SwiftUI
import CoreImage

enum ArtStyle: String, CaseIterable, Identifiable, Hashable {
    case chibi = "Chibi"
    case pixel = "Pixel Art"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .chibi: return "sparkles"
        case .pixel: return "square.grid.3x3.fill"
        }
    }

    var tagline: String {
        switch self {
        case .chibi: return "Big head, tiny body, sparkly eyes"
        case .pixel: return "Retro sprite with a real pixel grid"
        }
    }
}

enum Engine: String, CaseIterable, Identifiable {
    case onDevice = "On-device"
    case ai = "ChatGPT (free)"
    var id: String { rawValue }
}

/// Background shown behind the finished character.
enum Backdrop: String, CaseIterable, Identifiable {
    case transparent, peach, mint, sky, lavender, cream
    var id: String { rawValue }

    private var rgb: (top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat))? {
        switch self {
        case .transparent: return nil
        case .peach:    return ((1.00, 0.86, 0.86), (1.00, 0.72, 0.78))
        case .mint:     return ((0.86, 1.00, 0.93), (0.66, 0.92, 0.82))
        case .sky:      return ((0.84, 0.93, 1.00), (0.62, 0.80, 1.00))
        case .lavender: return ((0.93, 0.88, 1.00), (0.78, 0.70, 0.98))
        case .cream:    return ((1.00, 0.98, 0.90), (1.00, 0.90, 0.72))
        }
    }

    /// Top/bottom gradient colours for the chibi background.
    var gradient: (CIColor, CIColor)? {
        guard let c = rgb else { return nil }
        return (CIColor(red: c.top.0, green: c.top.1, blue: c.top.2),
                CIColor(red: c.bottom.0, green: c.bottom.1, blue: c.bottom.2))
    }

    /// Flat colour used behind pixel art.
    var solid: SIMD3<Float>? {
        guard let c = rgb else { return nil }
        return SIMD3(Float(c.bottom.0), Float(c.bottom.1), Float(c.bottom.2))
    }

    var swatch: Color {
        guard let c = rgb else { return .clear }
        return Color(red: c.bottom.0, green: c.bottom.1, blue: c.bottom.2)
    }
}

struct ChibiOptions: Equatable {
    /// How much the head is enlarged.
    var headScale: Double = 1.55
    /// Target height of the whole figure measured in heads (classic chibi is 2–3).
    var headsTall: Double = 2.6
    /// 0…1 strength of the big-anime-eyes warp.
    var eyeSize: Double = 0.6
    var inkLines = true
    var blush = true
    var catchlights = true
    var sticker = true
    var backdrop: Backdrop = .peach
}

struct PixelOptions: Equatable {
    var gridSize = 48
    var palette: PixelPalette = .auto
    var colorCount = 16
    var dithering = false
    var outline = true
    var removeBackground = true
    var backdrop: Backdrop = .sky

    static let gridSizes = [24, 32, 48, 64, 96]
}

enum PixelPalette: String, CaseIterable, Identifiable {
    case auto = "Auto (from photo)"
    case pico8 = "PICO-8"
    case sweetie16 = "Sweetie 16"
    case gameBoy = "Game Boy"
    case pastel = "Pastel Dream"
    case mono = "Mono"
    var id: String { rawValue }

    /// nil means "derive the palette from the image".
    var colors: [SIMD3<Float>]? {
        switch self {
        case .auto: return nil
        case .pico8:
            return hex(["000000", "1D2B53", "7E2553", "008751", "AB5236", "5F574F", "C2C3C7", "FFF1E8",
                        "FF004D", "FFA300", "FFEC27", "00E436", "29ADFF", "83769C", "FF77A8", "FFCCAA"])
        case .sweetie16:
            return hex(["1A1C2C", "5D275D", "B13E53", "EF7D57", "FFCD75", "A7F070", "38B764", "257179",
                        "29366F", "3B5DC9", "41A6F6", "73EFF7", "F4F4F4", "94B0C2", "566C86", "333C57"])
        case .gameBoy:
            return hex(["0F380F", "306230", "8BAC0F", "9BBC0F"])
        case .pastel:
            return hex(["3D3047", "6B5B95", "A28CC9", "F7CAC9", "F3A6B5", "E8737F", "FFE5B4", "FFD27F",
                        "B5EAD7", "7BC8A4", "A0D2EB", "5B8DB8", "FFFFFF", "C8B8A8", "8A6F5C", "4A3B32"])
        case .mono:
            return hex(["111111", "555555", "999999", "DDDDDD", "FFFFFF"])
        }
    }

    private func hex(_ values: [String]) -> [SIMD3<Float>] {
        values.compactMap { s in
            guard let v = UInt32(s, radix: 16) else { return nil }
            return SIMD3(Float((v >> 16) & 0xFF) / 255, Float((v >> 8) & 0xFF) / 255, Float(v & 0xFF) / 255)
        }
    }
}
