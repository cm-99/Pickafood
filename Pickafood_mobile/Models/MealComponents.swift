import Foundation

struct MealComponent: Identifiable, Codable {
    var id: String
    var name: String
    var mass_g: Double
    var base_calories_per_100g: Double
    var base_protein_per_100g: Double
    var base_fat_per_100g: Double
    var base_carbs_per_100g: Double

    var calories_kcal: Double { (mass_g / 100.0) * base_calories_per_100g }
    var protein_g: Double     { (mass_g / 100.0) * base_protein_per_100g }
    var fat_g: Double         { (mass_g / 100.0) * base_fat_per_100g }
    var carbs_g: Double       { (mass_g / 100.0) * base_carbs_per_100g }
}
