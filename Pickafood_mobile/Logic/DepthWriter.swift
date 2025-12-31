import Foundation
import CoreVideo
import CoreGraphics
import ImageIO
import MobileCoreServices

enum DepthWriter {

    static func write16bitPNG(from depthBuffer: CVPixelBuffer) throws -> URL {
        return try write16bitPNG(from: depthBuffer, cropInRGBSpace: nil, rgbSize: nil, orientation: .up)
    }

    static func write16bitPNG(from depthBuffer: CVPixelBuffer,
                              cropInRGBSpace: CGRect?,
                              rgbSize: CGSize?,
                              orientation: CGImagePropertyOrientation = .up) throws -> URL {

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(depthBuffer) == kCVPixelFormatType_DepthFloat32 else {
            throw NSError(domain: "DepthWriter", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Wymagany CVPixelFormatType_DepthFloat32"])
        }

        let dw = CVPixelBufferGetWidth(depthBuffer)
        let dh = CVPixelBufferGetHeight(depthBuffer)
        let dRowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else {
            throw NSError(domain: "DepthWriter", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Brak danych depth"])}
        let srcF32 = base.bindMemory(to: Float32.self, capacity: dRowBytes * dh / MemoryLayout<Float32>.size)

        var dx0 = 0, dy0 = 0, dCropW = dw, dCropH = dh
        if let roi = cropInRGBSpace, let rgbSize = rgbSize, rgbSize.width > 0, rgbSize.height > 0 {
            let sx = Double(dw) / Double(rgbSize.width)
            let sy = Double(dh) / Double(rgbSize.height)
            dx0 = max(0, min(dw-1, Int((roi.origin.x * sx).rounded(.down))))
            dy0 = max(0, min(dh-1, Int((roi.origin.y * sy).rounded(.down))))
            dCropW = max(1, min(dw - dx0, Int((roi.size.width  * sx).rounded(.toNearestOrEven))))
            dCropH = max(1, min(dh - dy0, Int((roi.size.height * sy).rounded(.toNearestOrEven))))
        }

        let outBytesPerRow = dCropW * MemoryLayout<UInt16>.size
        let outCount = dCropW * dCropH
        let mmData = UnsafeMutablePointer<UInt16>.allocate(capacity: outCount)
        var mmDataNeedsFree = true
        for y in 0..<dCropH {
            let syi = (dy0 + y) * (dRowBytes / MemoryLayout<Float32>.size)
            let srow = srcF32.advanced(by: syi)
            let drow = mmData.advanced(by: y * dCropW)
            for x in 0..<dCropW {
                let m = srow[dx0 + x] // metry (Float32)
                let mm = max(0.0, min(65535.0, Double(m * 1000.0)))
                drow[x] = UInt16(mm.rounded())
            }
        }

        let rot = rotationKind(for: orientation)
        var finalPtr: UnsafeMutablePointer<UInt16> = mmData
        var finalW = dCropW
        var finalH = dCropH
        var finalBytesPerRow = outBytesPerRow

        if rot != .none {
            let (rotPtr, rotW, rotH) = rotate(mmData, width: dCropW, height: dCropH, kind: rot)
            finalPtr = rotPtr
            finalW = rotW
            finalH = rotH
            finalBytesPerRow = finalW * MemoryLayout<UInt16>.size
            mmData.deallocate()
            mmDataNeedsFree = false
        }

        guard let cs = CGColorSpace(name: CGColorSpace.linearGray) else {
            if mmDataNeedsFree { mmData.deallocate() }
            if finalPtr != mmData { finalPtr.deallocate() }
            throw NSError(domain: "DepthWriter", code: -3, userInfo: nil)
        }

        guard let provider = CGDataProvider(dataInfo: nil, data: finalPtr,
                                            size: finalBytesPerRow * finalH,
                                            releaseData: {_,_,_ in }) else {
            if mmDataNeedsFree { mmData.deallocate() }
            if finalPtr != mmData { finalPtr.deallocate() }
            throw NSError(domain: "DepthWriter", code: -4, userInfo: nil)
        }

        guard let cg = CGImage(width: finalW, height: finalH,
                               bitsPerComponent: 16, bitsPerPixel: 16,
                               bytesPerRow: finalBytesPerRow, space: cs,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else {
            if mmDataNeedsFree { mmData.deallocate() }
            if finalPtr != mmData { finalPtr.deallocate() }
            throw NSError(domain: "DepthWriter", code: -5, userInfo: nil)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
            if mmDataNeedsFree { mmData.deallocate() }
            if finalPtr != mmData { finalPtr.deallocate() }
            throw NSError(domain: "DepthWriter", code: -6, userInfo: nil)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        let ok = CGImageDestinationFinalize(dest)

        // 5) Sprzątanie
        if mmDataNeedsFree { mmData.deallocate() }
        if finalPtr != mmData { finalPtr.deallocate() }
        if !ok {
            throw NSError(domain: "DepthWriter", code: -7, userInfo: nil)
        }
        return url
    }

    private enum RotationKind { case none, cw90, ccw90, r180 }

    private static func rotationKind(for orientation: CGImagePropertyOrientation) -> RotationKind {
        switch orientation {
        case .up:    return .none
        case .down:  return .r180
        case .right: return .cw90
        case .left:  return .ccw90
        default:     return .none
        }
    }

    private static func rotate(_ src: UnsafeMutablePointer<UInt16>,
                               width w: Int, height h: Int,
                               kind: RotationKind) -> (dst: UnsafeMutablePointer<UInt16>, outW: Int, outH: Int) {
        switch kind {
        case .none:
            let dst = UnsafeMutablePointer<UInt16>.allocate(capacity: w*h)
            dst.initialize(from: src, count: w*h)
            return (dst, w, h)

        case .r180:
            let dst = UnsafeMutablePointer<UInt16>.allocate(capacity: w*h)
            for y in 0..<h {
                let srcRow = src.advanced(by: y*w)
                let dstRow = dst.advanced(by: (h-1-y)*w)
                for x in 0..<w {
                    dstRow[w-1-x] = srcRow[x]
                }
            }
            return (dst, w, h)

        case .cw90:
            let outW = h, outH = w
            let dst = UnsafeMutablePointer<UInt16>.allocate(capacity: outW*outH)
            for y in 0..<h {
                for x in 0..<w {
                    let v = src[y*w + x]
                    let xp = h - 1 - y
                    let yp = x
                    dst[yp*outW + xp] = v
                }
            }
            return (dst, outW, outH)

        case .ccw90:
            let outW = h, outH = w
            let dst = UnsafeMutablePointer<UInt16>.allocate(capacity: outW*outH)
            for y in 0..<h {
                for x in 0..<w {
                    let v = src[y*w + x]
                    let xp = y
                    let yp = w - 1 - x
                    dst[yp*outW + xp] = v
                }
            }
            return (dst, outW, outH)
        }
    }
}

