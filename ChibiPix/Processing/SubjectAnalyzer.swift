import Vision
import CoreImage

enum SubjectKind: String {
    case person, animal, unknown

    var label: String {
        switch self {
        case .person: return "Person detected"
        case .animal: return "Animal detected"
        case .unknown: return "Subject detected"
        }
    }
}

/// Everything the renderers need to know about the photo.
/// All geometry is in Core Image pixel space: origin at the bottom-left of the (upright) image.
struct SubjectAnalysis {
    var imageSize: CGSize
    /// Soft foreground mask (white = subject). nil when segmentation was unavailable.
    var mask: CIImage?
    var subjectBounds: CGRect
    /// Region containing the head, including hair / ears.
    var headRect: CGRect
    var eyeCenters: [CGPoint]
    var pupils: [CGPoint]
    var eyeRadius: CGFloat
    var kind: SubjectKind
}

enum SubjectAnalyzer {
    static func analyze(_ cgImage: CGImage) -> SubjectAnalysis {
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let fullRect = CGRect(origin: .zero, size: size)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 1. Lift the subject (people, pets, most foreground objects) off the background.
        var mask = foregroundMask(handler: handler, size: size)
        var bounds = fullRect
        if let m = mask {
            if let b = maskBounds(m, size: size) { bounds = b } else { mask = nil }
        }

        var kind = SubjectKind.unknown
        var head: CGRect?
        var eyes: [CGPoint] = []
        var pupils: [CGPoint] = []
        var eyeRadius: CGFloat = 0

        // 2. Human face + landmarks.
        let faceRequest = VNDetectFaceLandmarksRequest()
        if (try? handler.perform([faceRequest])) != nil,
           let face = faceRequest.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            let f = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
            kind = .person
            // Vision's face box is roughly brow-to-chin; grow it to include hair and ears.
            head = CGRect(x: f.minX - f.width * 0.28, y: f.minY - f.height * 0.10,
                          width: f.width * 1.56, height: f.height * 1.75)
            if let lm = face.landmarks {
                for region in [lm.leftEye, lm.rightEye].compactMap({ $0 }) {
                    let pts = region.pointsInImage(imageSize: size)
                    guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
                          let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { continue }
                    eyes.append(CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2))
                    eyeRadius = max(eyeRadius, (maxX - minX) / 2)
                }
                for region in [lm.leftPupil, lm.rightPupil].compactMap({ $0 }) {
                    if let p = region.pointsInImage(imageSize: size).first { pupils.append(p) }
                }
            }
            if eyeRadius == 0 { eyeRadius = f.width * 0.1 }
        }

        // 3. Animal head via body-pose joints (cats & dogs).
        if kind == .unknown {
            let poseRequest = VNDetectAnimalBodyPoseRequest()
            if (try? handler.perform([poseRequest])) != nil,
               let observation = poseRequest.results?.first,
               let joints = try? observation.recognizedPoints(.head) {
                let good = joints.filter { $0.value.confidence > 0.3 }
                func px(_ p: VNRecognizedPoint) -> CGPoint {
                    CGPoint(x: p.location.x * size.width, y: p.location.y * size.height)
                }
                let points = good.values.map(px)
                if points.count >= 2,
                   let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                   let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
                    kind = .animal
                    let side = max(maxX - minX, maxY - minY, size.width * 0.05)
                    var r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                        .insetBy(dx: -side * 0.35, dy: -side * 0.35)
                    r.origin.y -= side * 0.25          // muzzle / chin below the nose
                    r.size.height += side * 0.25
                    head = r
                    let eyeJoints: [VNAnimalBodyPoseObservation.JointName] = [.leftEye, .rightEye]
                    for j in eyeJoints { if let p = good[j] { eyes.append(px(p)) } }
                    if eyes.count == 2 {
                        eyeRadius = hypot(eyes[0].x - eyes[1].x, eyes[0].y - eyes[1].y) * 0.2
                    } else {
                        eyeRadius = side * 0.08
                    }
                    pupils = eyes
                }
            }
        }

        // 4. Plain animal classification as a last resort for the label.
        if kind == .unknown {
            let animalRequest = VNRecognizeAnimalsRequest()
            if (try? handler.perform([animalRequest])) != nil, !(animalRequest.results ?? []).isEmpty {
                kind = .animal
            }
        }

        return SubjectAnalysis(imageSize: size, mask: mask, subjectBounds: bounds,
                               headRect: head ?? fallbackHead(in: bounds),
                               eyeCenters: eyes, pupils: pupils, eyeRadius: eyeRadius, kind: kind)
    }

    // MARK: - Helpers

    private static func area(_ r: CGRect) -> CGFloat { r.width * r.height }

    /// Without landmarks, assume the head sits at the top-centre of the subject.
    private static func fallbackHead(in bounds: CGRect) -> CGRect {
        let w = min(bounds.width * 0.7, bounds.height * 0.5)
        let h = min(bounds.height * 0.45, w * 1.1)
        return CGRect(x: bounds.midX - w / 2, y: bounds.maxY - h, width: w, height: h)
    }

    private static func foregroundMask(handler: VNImageRequestHandler, size: CGSize) -> CIImage? {
        // iOS 17 "lift subject" — handles people and animals. Not supported in the Simulator.
        let request = VNGenerateForegroundInstanceMaskRequest()
        if (try? handler.perform([request])) != nil,
           let observation = request.results?.first,
           let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) {
            return fitted(CIImage(cvPixelBuffer: buffer), to: size)
        }
        // Fallback: person-only segmentation.
        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .accurate
        if (try? handler.perform([person])) != nil, let buffer = person.results?.first?.pixelBuffer {
            return fitted(CIImage(cvPixelBuffer: buffer), to: size)
        }
        return nil
    }

    private static func fitted(_ image: CIImage, to size: CGSize) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return image }
        return image
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)
                .concatenating(CGAffineTransform(scaleX: size.width / e.width, y: size.height / e.height)))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Bounding box of the white part of the mask, or nil if it's (almost) empty.
    private static func maskBounds(_ mask: CIImage, size: CGSize) -> CGRect? {
        let scale = min(1, 256 / max(size.width, size.height))
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        let small = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ImageUtils.ciContext.createCGImage(small, from: CGRect(x: 0, y: 0, width: w, height: h)),
              let bitmap = RGBABitmap(cgImage: cg) else { return nil }

        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, count = 0
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.pixels[(y * bitmap.width + x) * 4] > 127 {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard count > (bitmap.width * bitmap.height) / 200 else { return nil }
        let sx = size.width / CGFloat(bitmap.width)
        let sy = size.height / CGFloat(bitmap.height)
        // Bitmap rows run top-down; Core Image runs bottom-up.
        return CGRect(x: CGFloat(minX) * sx,
                      y: size.height - CGFloat(maxY + 1) * sy,
                      width: CGFloat(maxX - minX + 1) * sx,
                      height: CGFloat(maxY - minY + 1) * sy)
    }
}
