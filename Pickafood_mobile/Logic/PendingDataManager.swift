import Foundation
import UIKit

struct PendingSample: Identifiable, Codable, Hashable {
    let id: String               // UUID
    let createdAt: Date
    let rgbPath: String
    let depthPath: String?
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let width: Int
    let height: Int
    let thumbnailPath: String?
}

final class PendingDataManager: ObservableObject {
    static let shared = PendingDataManager()

    @Published private(set) var samples: [PendingSample] = []
    private let storeURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storeURL = docs.appendingPathComponent("pending_samples.json")
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: storeURL)
            let decoded = try JSONDecoder().decode([PendingSample].self, from: data)
            samples = decoded
        } catch {
            samples = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(samples)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("[PendingData] Save error:", error)
        }
    }

    func add(_ s: PendingSample) {
        samples.append(s)
        save()
    }

    func remove(_ s: PendingSample, deleteFiles: Bool = false) {
        samples.removeAll { $0.id == s.id }
        save()
        if deleteFiles {
            if FileManager.default.fileExists(atPath: s.rgbPath) {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: s.rgbPath))
            }
            if let d = s.depthPath, FileManager.default.fileExists(atPath: d) {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: d))
            }
            if let t = s.thumbnailPath, FileManager.default.fileExists(atPath: t) {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: t))
            }
        }
    }

    func upload(_ sample: PendingSample,
                onPresentProgress: @escaping (_ taskID: String) -> Void,
                onError: @escaping (_ message: String) -> Void) async {

        guard let img = UIImage(contentsOfFile: sample.rgbPath)?.normalizedUp() else {
            onError("Nie udało się wczytać obrazu RGB (\(sample.rgbPath))")
            return
        }

        let depthURL: URL? = sample.depthPath.map { URL(fileURLWithPath: $0) }

        do {
            let taskID = try await APIClient.shared.analyse(
                rgb: img,
                depthURL: depthURL,
                fx: sample.fx, fy: sample.fy, cx: sample.cx, cy: sample.cy
            )
            onPresentProgress(taskID)

        } catch {
            onError("Nie udało się nawiązać połączenia z serwerem.")
        }
    }
    
    @discardableResult
    func saveCapture(_ payload: CapturePayload) async throws -> PendingSample {
        let id = UUID().uuidString
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        guard let jpg = payload.image.jpegData(compressionQuality: 0.92) else {
            throw NSError(domain: "PendingDataManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Nie udało się skompresować JPEG"])
        }
        let rgbURL = docs.appendingPathComponent("\(id).jpg")
        try jpg.write(to: rgbURL)

        var depthPath: String? = nil
        if let src = payload.depthURL {
            let dst = docs.appendingPathComponent("\(id)_depth.png")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
            depthPath = dst.path
        }

        let thumbURL = docs.appendingPathComponent("\(id)_thumb.jpg")
        let thumbData: Data? = autoreleasepool(invoking: {
            let maxSide: CGFloat = 300
            let scale = min(maxSide / max(payload.image.size.width, payload.image.size.height), 1.0)
            let size = CGSize(width: payload.image.size.width * scale, height: payload.image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let thumb = renderer.image { _ in
                payload.image.draw(in: CGRect(origin: .zero, size: size))
            }
            return thumb.jpegData(compressionQuality: 0.8)
        })
        if let t = thumbData { try? t.write(to: thumbURL) }

        let width  = Int(payload.image.size.width  * payload.image.scale)
        let height = Int(payload.image.size.height * payload.image.scale)

        let sample = PendingSample(
            id: id,
            createdAt: Date(),
            rgbPath: rgbURL.path,
            depthPath: depthPath,
            fx: payload.fx, fy: payload.fy, cx: payload.cx, cy: payload.cy,
            width: width, height: height,
            thumbnailPath: thumbData != nil ? thumbURL.path : nil
        )

        await MainActor.run {
            self.samples.append(sample)
            self.save()
        }
        return sample
    }
}

