import Foundation

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
    init?(stringValue: String) { self.stringValue = stringValue }
}

struct AnyDecodable: Decodable {
    let value: Any
    var doubleValue: Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self)    { value = i; return }
        if let s = try? c.decode(String.self) { value = s; return }
        if let b = try? c.decode(Bool.self)   { value = b; return }
        if let dict = try? c.decode([String: AnyDecodable].self) { value = dict; return }
        if let arr  = try? c.decode([AnyDecodable].self)         { value = arr; return }
        value = NSNull()
    }
}

public struct ServerMealEntry: Decodable {
    public let name: String
    public let weight_g: Double
    public let nutrients: [String: Double]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicCodingKey.self)
        var tmpName = ""
        var tmpWeight: Double = 0
        var tmpNutrients: [String: Double] = [:]

        for key in c.allKeys {
            switch key.stringValue {
            case "name":
                tmpName = try c.decode(String.self, forKey: key)
            case "weight_g":
                if let d = try? c.decode(Double.self, forKey: key) {
                    tmpWeight = d
                } else if let s = try? c.decode(String.self, forKey: key),
                          let d = Double(s.replacingOccurrences(of: ",", with: ".")) {
                    tmpWeight = d
                }
            default:
                if let d = try? c.decode(Double.self, forKey: key) {
                    tmpNutrients[key.stringValue] = d
                } else if let i = try? c.decode(Int.self, forKey: key) {
                    tmpNutrients[key.stringValue] = Double(i)
                } else if let s = try? c.decode(String.self, forKey: key),
                          let d = Double(s.replacingOccurrences(of: ",", with: ".")) {
                    tmpNutrients[key.stringValue] = d
                }
            }
        }
        self.name = tmpName
        self.weight_g = tmpWeight
        self.nutrients = tmpNutrients
    }
}

public struct ServerResult: Decodable {
    public let meal: [ServerMealEntry]
    public let total: [String: Double]
}

extension ServerMealEntry {
    init(name: String, weight_g: Double, nutrients: [String: Double]) {
        self.name = name
        self.weight_g = weight_g
        self.nutrients = nutrients
    }
}

extension ServerResult: Encodable {}
extension ServerMealEntry: Encodable {}
