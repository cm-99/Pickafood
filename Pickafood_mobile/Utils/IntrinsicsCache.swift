import Foundation
import simd
import UIKit
import ImageIO

struct IntrinsicsKey: Codable, Hashable {
    let device: String        
    let lens: String?
    let f35: Int?
}

struct IntrinsicsRecord: Codable {
    let fx: Double, fy: Double, cx: Double, cy: Double
    let width: Int, height: Int
    let date: Date
}

final class IntrinsicsCache {
    static let shared = IntrinsicsCache()
    private let udKey = "intrinsics_cache_v1"

    private var map: [IntrinsicsKey: IntrinsicsRecord] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: udKey),
           let d = try? JSONDecoder().decode([IntrinsicsKey: IntrinsicsRecord].self, from: data) {
            map = d
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    func store(from matrix: simd_float3x3, imageSize: CGSize,
               lensModel: String?, f35: Int?) {
        let (fx, fy, cx, cy) = (
            Double(matrix[0,0]), Double(matrix[1,1]),
            Double(matrix[2,0]), Double(matrix[2,1])
        )
        let key = IntrinsicsKey(device: hardwareID(),
                                lens: lensModel,
                                f35: f35)
        let rec = IntrinsicsRecord(fx: fx, fy: fy, cx: cx, cy: cy,
                                   width: Int(imageSize.width),
                                   height: Int(imageSize.height),
                                   date: Date())
        map[key] = rec
        save()
    }

    func lookup(for jpegData: Data, normalizedSize: CGSize) -> (Double,Double,Double,Double)? {
        let meta = exifMeta(jpegData)
        let candidateKeys: [IntrinsicsKey] = [
            IntrinsicsKey(device: hardwareID(), lens: meta.lensModel, f35: meta.f35),
            IntrinsicsKey(device: hardwareID(), lens: meta.lensModel, f35: nil),
            IntrinsicsKey(device: hardwareID(), lens: nil, f35: meta.f35)
        ]
        for k in candidateKeys {
            if let rec = map[k] {
                let (fx, fy, cx, cy) = GalleryIntrinsics.scaleIntrinsics(
                    fx: rec.fx, fy: rec.fy, cx: rec.cx, cy: rec.cy,
                    from: CGSize(width: rec.width, height: rec.height),
                    to: normalizedSize
                )
                return (fx, fy, cx, cy)
            }
        }
        return nil
    }

    private func hardwareID() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine.0) { ptr in
            String(cString: ptr)
        }
    }
    private func exifMeta(_ data: Data) -> (lensModel: String?, f35: Int?) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return (nil, nil) }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let lens = (exif?[kCGImagePropertyExifLensModel] ?? tiff?[kCGImagePropertyTIFFModel]) as? String
        let f35  = (exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.intValue
        return (lens, f35)
    }
}
