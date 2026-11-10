import CoreImage
import CoreGraphics

/// Turns the subject into a genuine low-resolution sprite: every output "pixel" is a single
/// palette colour on an exact grid, optionally with ordered dithering and a 1px outline.
enum PixelArtRenderer {
    static let targetSize = 1024

    static func render(image: CGImage, analysis a: SubjectAnalysis, options o: PixelOptions) -> CGImage? {
        let src = CIImage(cgImage: image)
        let extent = src.extent

        // 1. Punchier colours read better at low resolution.
        var subject = src.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.25,
            kCIInputContrastKey: 1.08,
        ])
        var crop = extent
        let cutOut = o.removeBackground && a.mask != nil
        if cutOut, let mask = a.mask {
            subject = subject.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
                kCIInputMaskImageKey: mask,
            ]).cropped(to: extent)
            let b = a.subjectBounds
            crop = b.insetBy(dx: -b.width * 0.03, dy: -b.height * 0.03).intersection(extent)
        }

        // 2. Grid dimensions (longest side = gridSize).
        let longest = max(crop.width, crop.height)
        let gw = max(1, Int((crop.width / longest * CGFloat(o.gridSize)).rounded()))
        let gh = max(1, Int((crop.height / longest * CGFloat(o.gridSize)).rounded()))

        // 3. Render at 4× the grid, then box-average each 4×4 block into one cell.
        let f = 4
        let bw = gw * f, bh = gh * f
        let sx = CGFloat(bw) / crop.width, sy = CGFloat(bh) / crop.height
        let prefiltered = (cutOut ? subject : subject.clampedToExtent())
            .applyingGaussianBlur(sigma: Double(0.5 / sx))
            .cropped(to: crop)
        let scaled = prefiltered.transformed(by:
            CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
                .concatenating(CGAffineTransform(scaleX: sx, y: sy)))
        guard let cg = ImageUtils.ciContext.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: bw, height: bh)),
              let big = RGBABitmap(cgImage: cg) else { return nil }

        var cells = [SIMD3<Float>](repeating: .zero, count: gw * gh)
        var opaque = [Bool](repeating: false, count: gw * gh)
        var samples: [SIMD3<Float>] = []
        samples.reserveCapacity(gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                var r: Float = 0, g: Float = 0, b: Float = 0, alpha: Float = 0
                for dy in 0..<f {
                    for dx in 0..<f {
                        let i = ((gy * f + dy) * big.width + gx * f + dx) * 4
                        r += Float(big.pixels[i])
                        g += Float(big.pixels[i + 1])
                        b += Float(big.pixels[i + 2])
                        alpha += Float(big.pixels[i + 3])
                    }
                }
                let idx = gy * gw + gx
                let coverage = alpha / Float(255 * f * f)
                if coverage >= 0.5 {
                    // Premultiplied sums / alpha sum = un-premultiplied colour in 0…1.
                    let c = SIMD3(r / alpha, g / alpha, b / alpha)
                    cells[idx] = c
                    opaque[idx] = true
                    samples.append(c)
                }
            }
        }
        guard !samples.isEmpty else { return nil }

        // 4. Palette.
        let palette = o.palette.colors ?? ColorQuantizer.kMeans(samples, k: o.colorCount)
        guard !palette.isEmpty else { return nil }
        let darkest = palette.min { ColorQuantizer.luma($0) < ColorQuantizer.luma($1) } ?? .zero
        let outlineColor = o.palette == .auto ? darkest * 0.45 : darkest

        // 5. Map every cell to the palette (with optional Bayer dithering) and draw outlines.
        let margin = (cutOut && o.outline) ? 1 : 0
        let ow = gw + margin * 2, oh = gh + margin * 2
        var out = RGBABitmap(width: ow, height: oh)
        let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        let spread: Float = o.dithering ? 0.14 : 0
        let background = o.backdrop.solid

        func isOpaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < gw && y < gh && opaque[y * gw + x]
        }

        for y in 0..<oh {
            for x in 0..<ow {
                let cx = x - margin, cy = y - margin
                if isOpaque(cx, cy) {
                    var c = cells[cy * gw + cx]
                    if spread > 0 {
                        c += SIMD3(repeating: (bayer[(y % 4) * 4 + x % 4] / 16 - 0.47) * spread)
                    }
                    out.set(x, y, ColorQuantizer.nearest(c, in: palette))
                } else if margin > 0,
                          isOpaque(cx - 1, cy) || isOpaque(cx + 1, cy) || isOpaque(cx, cy - 1) || isOpaque(cx, cy + 1) {
                    out.set(x, y, outlineColor)
                } else if let background {
                    out.set(x, y, background)
                }
            }
        }

        // 6. Crisp nearest-neighbour upscale.
        guard let small = out.makeCGImage() else { return nil }
        let factor = max(1, targetSize / max(ow, oh))
        return ImageUtils.upscaleNearest(small, factor: factor)
    }
}

enum ColorQuantizer {
    static func luma(_ c: SIMD3<Float>) -> Float { 0.299 * c.x + 0.587 * c.y + 0.114 * c.z }

    /// Perceptually weighted RGB distance.
    @inline(__always)
    static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return 2 * d.x * d.x + 4 * d.y * d.y + 3 * d.z * d.z
    }

    static func nearestIndex(_ c: SIMD3<Float>, in palette: [SIMD3<Float>]) -> Int {
        var best = 0
        var bestD = Float.greatestFiniteMagnitude
        for (i, p) in palette.enumerated() {
            let d = distance(c, p)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    static func nearest(_ c: SIMD3<Float>, in palette: [SIMD3<Float>]) -> SIMD3<Float> {
        palette[nearestIndex(c, in: palette)]
    }

    /// k-means++ clustering with a fixed seed, so the same photo always gives the same palette.
    static func kMeans(_ colors: [SIMD3<Float>], k requested: Int, iterations: Int = 12) -> [SIMD3<Float>] {
        guard !colors.isEmpty else { return [] }
        let k = max(1, min(requested, colors.count))
        var seed: UInt64 = 42
        func random() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) % 1_000_000) / 1_000_000
        }

        var centers = [colors[Int(random() * Float(colors.count - 1))]]
        var dists = colors.map { distance($0, centers[0]) }
        while centers.count < k {
            let total = dists.reduce(0, +)
            guard total > 0 else { break }
            var target = random() * total
            var chosen = dists.count - 1
            for (i, d) in dists.enumerated() {
                target -= d
                if target <= 0 { chosen = i; break }
            }
            let c = colors[chosen]
            centers.append(c)
            for i in dists.indices { dists[i] = min(dists[i], distance(colors[i], c)) }
        }

        for _ in 0..<iterations {
            var sums = [SIMD3<Float>](repeating: .zero, count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for c in colors {
                let j = nearestIndex(c, in: centers)
                sums[j] += c
                counts[j] += 1
            }
            var moved = false
            for j in centers.indices where counts[j] > 0 {
                let updated = sums[j] / Float(counts[j])
                if distance(updated, centers[j]) > 1e-6 { moved = true }
                centers[j] = updated
            }
            if !moved { break }
        }
        return centers
    }
}
