import Foundation
import UIKit

struct AnalyseResponse: Decodable { let task_id: String }

struct StatusResponse: Decodable {
    let state: String
    let label: String
    let step: Int
    let total: Int
    let result_ready: Bool
    
    init(){
        state = ""
        label = ""
        step = 0
        total = 0
        result_ready = false
    }
}

final class APIClient {
    static let shared = APIClient()

    private let base: URL
    private let session: URLSession
    private let basicAuthHeader: String?

    init(baseURL: URL = APIConfig.baseURL) {
        self.base = baseURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = APIConfig.requestTimeout
        cfg.timeoutIntervalForResource = APIConfig.resourceTimeout
        self.session = URLSession(configuration: cfg)

        if !APIConfig.basicUser.isEmpty || !APIConfig.basicPass.isEmpty {
            let creds = "\(APIConfig.basicUser):\(APIConfig.basicPass)"
            let token = Data(creds.utf8).base64EncodedString()
            self.basicAuthHeader = "Basic \(token)"
        } else {
            self.basicAuthHeader = nil
        }
    }

    private func makeRequest(path: String,
                             method: String = "GET",
                             contentType: String? = nil) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        if let ct = contentType { req.setValue(ct, forHTTPHeaderField: "Content-Type") }
        if let auth = basicAuthHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
        req.setValue("Pickafood/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return req
    }

    static func ensureOK(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "APIClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
    }

    func analyse(rgb: UIImage, depthURL: URL? = nil,
                 fx: Double, fy: Double, cx: Double, cy: Double) async throws -> String {

        var mb = MultipartBuilder()
        try mb.add(image: rgb, name: "rgb", filename: "rgb.jpg", jpegQuality: 0.9)
        try mb.add(fileURL: depthURL, name: "depth")
        mb.add(field: "fx", value: String(fx))
        mb.add(field: "fy", value: String(fy))
        mb.add(field: "cx", value: String(cx))
        mb.add(field: "cy", value: String(cy))

        let (body, boundary) = mb.build()

        var request = makeRequest(path: "analyse", method: "POST",
                                  contentType: "multipart/form-data; boundary=\(boundary)")
        request.httpBody = body

        let (data, resp) = try await session.data(for: request)
        try Self.ensureOK(resp)
        return try JSONDecoder().decode(AnalyseResponse.self, from: data).task_id
    }

    func status(taskID: String) async throws -> StatusResponse {
        let req = makeRequest(path: "task/\(taskID)")
        let (data, resp) = try await session.data(for: req)
        do {
            try Self.ensureOK(resp)
        } catch {
            throw error
        }
        
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    func result(taskID: String) async throws -> ServerResult {
        let req = makeRequest(path: "result/\(taskID)")
        let (data, resp) = try await session.data(for: req)
        try Self.ensureOK(resp)
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try dec.decode(ServerResult.self, from: data)
    }
    
    func submitReviewed(taskID: String, reviewed: ServerResult) async throws {
        var req = makeRequest(path: "task/\(taskID)/review", method: "POST",
                              contentType: "application/json; charset=utf-8")
        let enc = JSONEncoder()
        req.httpBody = try enc.encode(reviewed)
        let (_, resp) = try await session.data(for: req)
        try Self.ensureOK(resp)
    }
}

