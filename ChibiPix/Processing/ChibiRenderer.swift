import CoreImage
import CoreGraphics

/// On-device chibi: cuts the subject out, gives it an anime cel-shaded look,
/// enlarges the eyes, then re-proportions the figure (big head, short stubby body)
/// and finishes it as a sticker on a pastel background.
enum ChibiRenderer {
    static let outputSize: CGFloat = 1024

    static func render(image: CGImage, analysis a: SubjectAnalysis, options o: ChibiOptions) -> CGImage? {
        let src = CIImage(cgImage: image)
        let extent = src.extent
        let clear = CIImage(color: .clear).cropped(to: extent)
        let mask = a.mask ?? CIImage(color: .white).cropped(to: extent)

        // 1. Big anime eyes: bulge the image around each eye.
        var base = src
        if o.eyeSize > 0.01 {
            for eye in a.eyeCenters {
                base = base.applyingFilter("CIBumpDistortion", parameters: [
                    kCIInputCenterKey: CIVector(cgPoint: eye),
                    kCIInputRadiusKey: a.eyeRadius * 2.4,
                    kCIInputScaleKey: 0.55 * o.eyeSize,
                ]).cropped(to: extent)
            }
        }

        // 2. Cel shading + ink.
        var art = celShade(base, extent: extent, inkLines: o.inkLines)

        // 3. Face accents.
        if o.blush, a.eyeCenters.count == 2 {
            let midX = (a.eyeCenters[0].x + a.eyeCenters[1].x) / 2
            for eye in a.eyeCenters {
                let outward: CGFloat = eye.x < midX ? -1 : 1
                let c = CGPoint(x: eye.x + outward * a.eyeRadius * 0.35, y: eye.y - a.eyeRadius * 2.1)
                art = spot(center: c, radius: a.eyeRadius * 1.5,
                           color: CIColor(red: 1, green: 0.45, blue: 0.55, alpha: 0.45), hardness: 0)
                    .composited(over: art)
            }
        }
        if o.catchlights {
            let points = a.pupils.isEmpty ? a.eyeCenters : a.pupils
            let r = a.eyeRadius * (0.22 + 0.14 * CGFloat(o.eyeSize))
            let white = CIColor(red: 1, green: 1, blue: 1, alpha: 0.95)
            for p in points {
                art = spot(center: CGPoint(x: p.x - r * 0.9, y: p.y + r * 0.9), radius: r, color: white, hardness: 0.75)
                    .composited(over: art)
                art = spot(center: CGPoint(x: p.x + r * 0.9, y: p.y - r * 0.7), radius: r * 0.5, color: white, hardness: 0.7)
                    .composited(over: art)
            }
        }
        art = art.cropped(to: extent)

        // 4. Cut out the subject.
        let subject = art.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: mask,
        ]).cropped(to: extent)

        // 5. Re-proportion: split at the neck, scale the head up and squash the body.
        let s = a.subjectBounds
        let head = a.headRect
        let neckY = min(max(head.minY, s.minY), s.maxY)
        let fade = max(4, head.height * 0.10)
        let pivot = CGPoint(x: head.midX, y: neckY)
        let hs = CGFloat(o.headScale)

        // Feather the bottom of the head so it blends over the body.
        let headFade = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: neckY),
            "inputPoint1": CIVector(x: 0, y: neckY + fade),
            "inputColor0": CIColor.black,
            "inputColor1": CIColor.white,
        ])!.outputImage!.cropped(to: extent)
        let headPart = subject.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: headFade,
        ]).cropped(to: CGRect(x: extent.minX, y: neckY, width: extent.width, height: extent.maxY - neckY))

        let headRegion = CGRect(x: s.minX, y: neckY, width: s.width, height: s.maxY - neckY)
        let bodyRegion = CGRect(x: s.minX, y: s.minY, width: s.width, height: neckY + fade - s.minY).intersection(s)

        let bodyHeight = neckY - s.minY
        var bodySX: CGFloat = 1, bodySY: CGFloat = 1
        if bodyHeight > 1 {
            let targetBody = head.height * hs * CGFloat(o.headsTall - 1)
            bodySY = min(1, max(0.3, targetBody / bodyHeight))
            bodySX = min(1, max(0.7, bodySY + 0.35))
        }
        let headT = ImageUtils.scale(about: pivot, sx: hs, sy: hs)
            .concatenating(CGAffineTransform(translationX: 0, y: -fade * hs * 0.6))
        let bodyT = ImageUtils.scale(about: pivot, sx: bodySX, sy: bodySY)

        var figure = headPart.transformed(by: headT)
        var content = headRegion.applying(headT)
        if !bodyRegion.isNull, bodyRegion.height > 1 {
            figure = figure.composited(over: subject.cropped(to: bodyRegion).transformed(by: bodyT))
            content = content.union(bodyRegion.applying(bodyT))
        }
        guard content.width > 1, content.height > 1 else { return nil }

        // 6. Sticker outline + drop shadow.
        let unit = max(content.width, content.height) / 100
        var layered = figure
        if o.sticker {
            let ink = silhouette(figure, radius: unit * 0.5, color: CIColor(red: 0.25, green: 0.14, blue: 0.18))
            let border = silhouette(figure, radius: unit * 2.2, color: .white)
            let shadow = silhouette(figure, radius: unit * 2.2, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.22))
                .applyingGaussianBlur(sigma: Double(unit * 1.2))
                .transformed(by: CGAffineTransform(translationX: unit * 0.6, y: -unit * 1.2))
            layered = figure.composited(over: ink).composited(over: border).composited(over: shadow)
            content = content.insetBy(dx: -unit * 4, dy: -unit * 4)
        }

        // 7. Square canvas + background.
        let side = max(content.width, content.height) * 1.12
        let canvas = CGRect(x: content.midX - side / 2, y: content.midY - side / 2, width: side, height: side)
        var composed = layered
        if let bg = background(o.backdrop, in: canvas) {
            composed = layered.composited(over: bg)
        }
        let k = outputSize / side
        composed = composed.cropped(to: canvas).transformed(by:
            CGAffineTransform(translationX: -canvas.minX, y: -canvas.minY)
                .concatenating(CGAffineTransform(scaleX: k, y: k)))
        return ImageUtils.ciContext.createCGImage(composed, from: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
    }

    // MARK: - Building blocks

    /// Flattened, saturated colour with dark line art – the classic anime "cel" look.
    static func celShade(_ image: CIImage, extent: CGRect, inkLines: Bool) -> CIImage {
        let sigma = Double(max(1.0, extent.width / 600))
        let smooth = image.applyingFilter("CIMedianFilter")
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: extent)
        let posterized = smooth
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.35,
                kCIInputBrightnessKey: 0.03,
                kCIInputContrastKey: 1.05,
            ])
            .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 8])
        let flat = posterized.clampedToExtent().applyingGaussianBlur(sigma: 0.6).cropped(to: extent)
        guard inkLines else { return flat }

        let lines = smooth.applyingFilter("CILineOverlay", parameters: [
            "inputNRNoiseLevel": 0.07,
            "inputNRSharpness": 0.71,
            "inputEdgeIntensity": 1.0,
            "inputThreshold": 0.12,
            "inputContrast": 50.0,
        ])
        .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.85),
            "inputBiasVector": CIVector(x: 0.22, y: 0.12, z: 0.12, w: 0),
        ])
        .cropped(to: extent)
        return lines.composited(over: flat)
    }

    /// Dilated, single-colour copy of the figure's alpha – used for outlines and shadows.
    static func silhouette(_ image: CIImage, radius: CGFloat, color: CIColor) -> CIImage {
        image
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: color.alpha),
                "inputBiasVector": CIVector(x: color.red, y: color.green, z: color.blue, w: 0),
            ])
    }

    /// Soft or hard-edged round dot.
    static func spot(center: CGPoint, radius: CGFloat, color: CIColor, hardness: CGFloat) -> CIImage {
        let transparent = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(cgPoint: center),
            "inputRadius0": radius * max(0, min(0.99, hardness)),
            "inputRadius1": radius,
            "inputColor0": color,
            "inputColor1": transparent,
        ])!.outputImage!
        return gradient.cropped(to: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Pastel gradient with a soft halo and a sprinkle of bokeh dots.
    static func background(_ backdrop: Backdrop, in rect: CGRect) -> CIImage? {
        guard let colors = backdrop.gradient else { return nil }
        var bg = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: rect.midX, y: rect.maxY),
            "inputPoint1": CIVector(x: rect.midX, y: rect.minY),
            "inputColor0": colors.0,
            "inputColor1": colors.1,
        ])!.outputImage!.cropped(to: rect)

        bg = spot(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.45,
                  color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.35), hardness: 0.55).composited(over: bg)

        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        for _ in 0..<16 {
            let c = CGPoint(x: rect.minX + random() * rect.width, y: rect.minY + random() * rect.height)
            let r = rect.width * (0.006 + 0.018 * random())
            bg = spot(center: c, radius: r, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.6), hardness: 0.7)
                .composited(over: bg)
        }
        return bg.cropped(to: rect)
    }
}
