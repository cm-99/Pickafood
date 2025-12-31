import UIKit

extension UIImage {
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }

        let ps = self.pixelSize
        let outSize: CGSize
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            outSize = CGSize(width: ps.h, height: ps.w)
        default:
            outSize = CGSize(width: ps.w, height: ps.h)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)

        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: outSize))
        }
    }

    var pixelSize: (w: Int, h: Int) {
        if let cg = self.cgImage { return (cg.width, cg.height) }
        return (Int(size.width * scale), Int(size.height * scale))
    }
}
