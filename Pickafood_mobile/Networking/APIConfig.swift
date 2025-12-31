import Foundation

enum APIConfig {
    static let baseURL = "DOMENA"

    // Basic-Auth
    static let basicUser: String = ""
    static let basicPass: String = ""

    // Timeouty połączeń
    static let requestTimeout: TimeInterval  = 10
    static let resourceTimeout: TimeInterval = 15
}

