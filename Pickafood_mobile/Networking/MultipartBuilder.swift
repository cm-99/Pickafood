import Foundation
import UIKit

struct MultipartBuilder {
    private let boundary: String
    private var body = Data()
    private var closed = false

    init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    @discardableResult
    mutating func add(field name: String, value: String) -> MultipartBuilder {
        precondition(!closed, "Multipart already built")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
        return self
    }

    @discardableResult
    mutating func add(image: UIImage, name: String, filename: String = "image.jpg", jpegQuality: CGFloat = 0.9) throws -> MultipartBuilder {
        precondition(!closed, "Multipart already built")
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw NSError(domain: "MultipartBuilder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nie udało się zakodować JPEG"])
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        append("\r\n")
        return self
    }

    @discardableResult
    mutating func add(fileURL: URL?, name: String, filename: String? = nil, mimeType: String? = nil) throws -> MultipartBuilder {
        precondition(!closed, "Multipart already built")
        guard let url = fileURL else { return self }
        let data = try Data(contentsOf: url)

        let fn = filename ?? url.lastPathComponent
        let mt = mimeType ?? mimeTypeFromExtension(url.pathExtension)

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fn)\"\r\n")
        append("Content-Type: \(mt)\r\n\r\n")
        body.append(data)
        append("\r\n")
        return self
    }

    mutating func build() -> (Data, String) {
        precondition(!closed, "Multipart already built")
        append("--\(boundary)--\r\n")
        closed = true
        return (body, boundary)
    }

    private mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) {
            body.append(d)
        }
    }

    private func mimeTypeFromExtension(_ ext: String) -> String {
        let e = ext.lowercased()
        switch e {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "heic":        return "image/heic"
        case "json":        return "application/json"
        case "txt":         return "text/plain"
        default:            return "application/octet-stream"
        }
    }
}
