import Foundation
import ImageIO
import CoreGraphics
import UIKit

enum GalleryIntrinsics {

    static func estimate(from jpegData: Data,
                         imageSize: CGSize) -> (Double, Double, Double, Double)? {
        let W = max(1.0, Double(imageSize.width))
        let H = max(1.0, Double(imageSize.height))

        let cx = (W - 1.0) / 2.0
        let cy = (H - 1.0) / 2.0

        guard let src = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else {
            return fallback(W: W, H: H, cx: cx, cy: cy)
        }

        if let f35 = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue,
           f35 > 0, f35 < 200 {
            // Przekątna klatki 35mm
            let diag35 = sqrt(36.0*36.0 + 24.0*24.0)
            let fovDiag = 2.0 * atan(diag35 / (2.0 * f35)) // rad
            let diagPx  = hypot(W, H)
            let fpx = 0.5 * diagPx / tan(0.5 * fovDiag)   // ogniskowa w pikselach po przekątnej

            let fx = fpx
            let fy = fpx

            if fx.isFinite, fy.isFinite, fx > 200, fy > 200, fx < 10000, fy < 10000 {
                return (fx, fy, cx, cy)
            }
        }

        return fallback(W: W, H: H, cx: cx, cy: cy)
    }

    private static func fallback(W: Double, H: Double, cx: Double, cy: Double)
      -> (Double, Double, Double, Double) {
        let fovX = 63.0 * .pi / 180.0
        let fovY = 48.0 * .pi / 180.0
        let fx = 0.5 * W / tan(0.5 * fovX)
        let fy = 0.5 * H / tan(0.5 * fovY)
        return (fx, fy, cx, cy)
    }

    static func scaleIntrinsics(fx: Double, fy: Double, cx: Double, cy: Double,
                                from src: CGSize, to dst: CGSize) -> (Double, Double, Double, Double) {
        let sx = Double(dst.width / max(1, src.width))
        let sy = Double(dst.height / max(1, src.height))
        return (fx*sx, fy*sy, cx*sx, cy*sy)
    }
}
