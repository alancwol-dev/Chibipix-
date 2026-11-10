import UIKit
import CoreImage

enum ImageUtils {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Redraws the image so its orientation is `.up`, it uses standard (non-HDR) colour,
    /// and its longest side is at most `maxDimension` pixels.
    static func normalized(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, (size.width * scale).rounded()),
                            height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Draws `image` into a larger canvas with no smoothing (for crisp pixel art).
    static func upscaleNearest(_ image: CGImage, factor: Int) -> CGImage? {
        guard factor > 1 else { return image }
        let w = image.width * factor, h = image.height * factor
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Scale about a fixed point.
    static func scale(about p: CGPoint, sx: CGFloat, sy: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: p.x, y: p.y)
            .scaledBy(x: sx, y: sy)
            .translatedBy(x: -p.x, y: -p.y)
    }
}

/// Simple RGBA8 (premultiplied) pixel buffer. Row 0 is the top row of the image.
struct RGBABitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: ImageUtils.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        pixels = data
    }

    /// Writes an opaque colour (components 0…1).
    mutating func set(_ x: Int, _ y: Int, _ c: SIMD3<Float>) {
        let i = (y * width + x) * 4
        pixels[i]     = UInt8(max(0, min(255, (c.x * 255).rounded())))
        pixels[i + 1] = UInt8(max(0, min(255, (c.y * 255).rounded())))
        pixels[i + 2] = UInt8(max(0, min(255, (c.z * 255).rounded())))
        pixels[i + 3] = 255
    }

    func makeCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: ImageUtils.sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
