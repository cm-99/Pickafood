import Foundation

struct LocalMealHistoryItem: Identifiable, Codable {
    let id: UUID
    let date: Date
    let thumbnailName: String? // miniatura zdjęcia
    var summary: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var rawResult: MealResult
}
