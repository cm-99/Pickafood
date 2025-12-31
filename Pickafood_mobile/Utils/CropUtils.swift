import Foundation
import CoreImage
import UIKit

struct CroppedImageResult {
    let image: UIImage
    let cropRectInOriginal: CGRect
    let outputSize: CGSize
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
}

enum CropUtils {

    static func centerSquareCropAndResize(ciImage: CIImage,
                                          rawWidth: Int,
                                          rawHeight: Int,
                                          fx: Double, fy: Double, cx: Double, cy: Double,
                                          outputSize: CGSize = CGSize(width: 1024, height: 1024)) -> CroppedImageResult? {

        let W = rawWidth, H = rawHeight
        let side = min(W, H)
        let x0 = (W - side) / 2
        let y0 = (H - side) / 2
        let cropRect = CGRect(x: x0, y: y0, width: side, height: side)

        let cropped = ciImage.cropped(to: cropRect)
        let scaleX = outputSize.width / CGFloat(side)
        let scaleY = outputSize.height / CGFloat(side)

        let resized = cropped.transformed(by:
            CGAffineTransform(scaleX: scaleX, y: scaleY)
        )

        let ctx = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(resized, from: CGRect(origin: .zero, size: outputSize)) else { return nil }
        let outImage = UIImage(cgImage: cg, scale: 1.0, orientation: .up)

        let fx2 = fx * Double(scaleX)
        let fy2 = fy * Double(scaleY)
        let cx2 = (cx - Double(x0)) * Double(scaleX)
        let cy2 = (cy - Double(y0)) * Double(scaleY)

        return CroppedImageResult(image: outImage,
                                  cropRectInOriginal: cropRect,
                                  outputSize: outputSize,
                                  fx: fx2, fy: fy2, cx: cx2, cy: cy2)
    }
}
