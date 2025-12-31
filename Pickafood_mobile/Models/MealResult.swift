import Foundation

struct MealResult: Codable {
    var meal: [MealComponent]
    var photoFilename: String?
}
