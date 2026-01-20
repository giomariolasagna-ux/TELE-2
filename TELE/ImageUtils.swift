import Foundation

#if canImport(UIKit)
import UIKit

enum ImageUtilsError: Error {
    case invalidImageData
    case cropFailed
    case imageEncodeFailed
}

enum ImageUtils {
    /// Crop a full-resolution image to simulate a digital zoom at a given center.
    /// - Parameters:
    ///   - fullData: The full frame image data (JPEG/PNG)
    ///   - zoomFactor: Desired zoom (>= 1.0)
    ///   - centerNorm: Center point in normalized coordinates [0,1]
    ///   - outputMaxDimension: Optional max longer-side dimension for the output to limit payload
    ///   - outputJPEGQuality: JPEG compression quality [0, 1], default 0.9
    ///   - forceSquare: If true, returns a 1:1 square crop (required for OpenAI)
    /// - Returns: (cropData, cropRectNorm, fullW, fullH, cropW, cropH)
    static func cropForZoom(fullData: Data,
                            zoomFactor: CGFloat,
                            centerNorm: CGPoint,
                            outputMaxDimension: CGFloat = 1600,
                            outputJPEGQuality: CGFloat = 0.9,
                            forceSquare: Bool = false) throws -> (Data, CGRect, Int, Int, Int, Int) {
        // Sanitize inputs
        let zIn = zoomFactor.isFinite && zoomFactor >= 1 ? zoomFactor : 1
        let cX = centerNorm.x.isFinite ? centerNorm.x : 0.5
        let cY = centerNorm.y.isFinite ? centerNorm.y : 0.5
        let cxNorm = min(max(cX, 0), 1)
        let cyNorm = min(max(cY, 0), 1)
        #if DEBUG
        if zoomFactor != zIn || cX != cxNorm || cY != cyNorm {
            print("[ImageUtils] sanitized inputs: z=\(zIn), cx=\(cxNorm), cy=\(cyNorm)")
        }
        #endif
        
        guard let img = UIImage(data: fullData) else { throw ImageUtilsError.invalidImageData }
        // Normalize orientation to .up to ensure crop rects align with pixel buffer
        let baseCG: CGImage
        if let cg0 = img.cgImage, img.imageOrientation == .up {
            baseCG = cg0
        } else {
            let pixelSize = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1 // we are working in pixels explicitly
            let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
            let upright = renderer.image { _ in
                img.draw(in: CGRect(origin: .zero, size: pixelSize))
            }
            guard let cg1 = upright.cgImage else { throw ImageUtilsError.invalidImageData }
            baseCG = cg1
        }

        let fullW = baseCG.width
        let fullH = baseCG.height
        let z = zIn

        // crop size on the original image corresponding to the zoom
        let cropWFloat = CGFloat(fullW) / z
        let cropHFloat = CGFloat(fullH) / z

        var cropW = min(max(cropWFloat, 1), CGFloat(fullW))
        var cropH = min(max(cropHFloat, 1), CGFloat(fullH))
        
        if forceSquare {
            let side = min(cropW, cropH)
            cropW = side
            cropH = side
            TeleLogger.shared.log("ForceSquare enabled: side \(Int(side))px", area: "IMAGE")
        }

        // center in pixels
        let cx = cxNorm * CGFloat(fullW)
        let cy = cyNorm * CGFloat(fullH)

        var ox = cx - cropW / 2.0
        var oy = cy - cropH / 2.0
        ox = max(0, min(ox, CGFloat(fullW) - cropW))
        oy = max(0, min(oy, CGFloat(fullH) - cropH))

        let cropRect = CGRect(x: ox, y: oy, width: cropW, height: cropH)
        guard let croppedCg = baseCG.cropping(to: cropRect) else { throw ImageUtilsError.cropFailed }
        let cropped = UIImage(cgImage: croppedCg, scale: 1, orientation: .up)

        // Resize if needed
        let longer = max(cropped.size.width, cropped.size.height)
        let maxDim = min(max(1, outputMaxDimension), 4096)
        let scale = maxDim > 0 ? min(1.0, maxDim / longer) : 1.0
        let newSize = CGSize(width: cropped.size.width * scale, height: cropped.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: newSize))
        }

        guard let jpeg = resized.jpegData(compressionQuality: outputJPEGQuality) else { throw ImageUtilsError.imageEncodeFailed }

        let cropRectNorm = CGRect(x: cropRect.origin.x / CGFloat(fullW),
                                  y: cropRect.origin.y / CGFloat(fullH),
                                  width: cropRect.size.width / CGFloat(fullW),
                                  height: cropRect.size.height / CGFloat(fullH))

        return (jpeg, cropRectNorm, fullW, fullH, Int(round(cropRect.width)), Int(round(cropRect.height)))
    }
}

#else
import AppKit

enum ImageUtilsError: Error {
    case invalidImageData
    case cropFailed
    case imageEncodeFailed
}

enum ImageUtils {
    static func cropForZoom(fullData: Data,
                            zoomFactor: CGFloat,
                            centerNorm: CGPoint,
                            outputMaxDimension: CGFloat = 1600,
                            outputJPEGQuality: CGFloat = 0.9,
                            forceSquare: Bool = false) throws -> (Data, CGRect, Int, Int, Int, Int) {
        // Sanitize inputs
        let zIn = zoomFactor.isFinite && zoomFactor >= 1 ? zoomFactor : 1
        let cX = centerNorm.x.isFinite ? centerNorm.x : 0.5
        let cY = centerNorm.y.isFinite ? centerNorm.y : 0.5
        let cxNorm = min(max(cX, 0), 1)
        let cyNorm = min(max(cY, 0), 1)
        #if DEBUG
        if zoomFactor != zIn || cX != cxNorm || cY != cyNorm {
            print("[ImageUtils] sanitized inputs: z=\(zIn), cx=\(cxNorm), cy=\(cyNorm)")
        }
        #endif
        
        // Decode NSImage and obtain CGImage
        guard let nsImage = NSImage(data: fullData) else { throw ImageUtilsError.invalidImageData }
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { throw ImageUtilsError.invalidImageData }

        let fullW = cg.width
        let fullH = cg.height
        let z = zIn

        // crop size corresponding to zoom
        let cropWFloat = CGFloat(fullW) / z
        let cropHFloat = CGFloat(fullH) / z

        var cropW = min(max(cropWFloat, 1), CGFloat(fullW))
        var cropH = min(max(cropHFloat, 1), CGFloat(fullH))
        
        if forceSquare {
            let side = min(cropW, cropH)
            cropW = side
            cropH = side
            TeleLogger.shared.log("ForceSquare enabled: side \(Int(side))px", area: "IMAGE")
        }

        // center in pixels (clamped)
        let cx = cxNorm * CGFloat(fullW)
        let cy = cyNorm * CGFloat(fullH)

        var ox = cx - cropW / 2.0
        var oy = cy - cropH / 2.0
        ox = max(0, min(ox, CGFloat(fullW) - cropW))
        oy = max(0, min(oy, CGFloat(fullH) - cropH))

        let cropRect = CGRect(x: ox, y: oy, width: cropW, height: cropH)
        guard let croppedCg = cg.cropping(to: cropRect) else { throw ImageUtilsError.cropFailed }

        // Resize to outputMaxDimension keeping aspect ratio
        let croppedSize = CGSize(width: croppedCg.width, height: croppedCg.height)
        let longer = max(croppedSize.width, croppedSize.height)
        let maxDim = min(max(1, outputMaxDimension), 4096)
        let scale = maxDim > 0 ? min(1.0, maxDim / longer) : 1.0
        let newSize = CGSize(width: croppedSize.width * scale, height: croppedSize.height * scale)

        // Render into a new context
        guard let colorSpace = croppedCg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { throw ImageUtilsError.imageEncodeFailed }
        guard let ctx = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageUtilsError.imageEncodeFailed }

        ctx.interpolationQuality = .high
        ctx.draw(croppedCg, in: CGRect(origin: .zero, size: newSize))
        guard let resizedCg = ctx.makeImage() else { throw ImageUtilsError.imageEncodeFailed }

        let resizedRep = NSBitmapImageRep(cgImage: resizedCg)
        guard let jpeg = resizedRep.representation(using: .jpeg, properties: [.compressionFactor: outputJPEGQuality]) else {
            throw ImageUtilsError.imageEncodeFailed
        }

        let cropRectNorm = CGRect(x: cropRect.origin.x / CGFloat(fullW),
                                  y: cropRect.origin.y / CGFloat(fullH),
                                  width: cropRect.size.width / CGFloat(fullW),
                                  height: cropRect.size.height / CGFloat(fullH))

        let cw = Int(round(cropRect.width))
        let ch = Int(round(cropRect.height))
        return (jpeg, cropRectNorm, fullW, fullH, cw, ch)
    }
}
#endif
