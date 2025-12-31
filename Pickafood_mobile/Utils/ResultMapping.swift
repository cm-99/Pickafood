import Foundation
import UIKit

enum ResultMapper {
    static func canonicalMacros(from dict: [String: Double]) -> (kcal: Double, pro: Double, fat: Double, carb: Double) {
        var kcal = 0.0, pro = 0.0, fat = 0.0, carb = 0.0
        for (k, v) in dict {
            let key = k.lowercased()
            if key.contains("kcal") || key.contains("kalor") { kcal = v }
            else if key.contains("biał") || key.contains("bial") || key.contains("protein") { pro = v }
            else if key.contains("tłus") || key.contains("tlus") || key.contains("fat") { fat = v }
            else if key.contains("węgl") || key.contains("wegl") || key.contains("carb") { carb = v }
        }
        return (kcal, pro, fat, carb)
    }

    static func saveThumbnail(_ image: UIImage?) -> String? {
        guard let img = image, let data = img.jpegData(compressionQuality: 0.85) else { return nil }
        let filename = UUID().uuidString + ".jpg"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        do { try data.write(to: url); return url.path } catch { return nil }
    }

    // Generuje tytuł na podstawie 1–2 najcięższych składników
    static func generateTitle(from components: [MealComponent]) -> String {
        let sorted = components.sorted { $0.mass_g > $1.mass_g }
        guard let first = sorted.first else { return "Posiłek" }
        if sorted.count == 1 { return first.name.capitalized }
        let second = sorted[1]
        return "\(first.name.capitalized), \(second.name.lowercased())"
    }

    static func makeLocalItem(from server: ServerResult, thumbnail: UIImage?) -> LocalMealHistoryItem {
        var comps: [MealComponent] = []
        for e in server.meal {
            let macros = canonicalMacros(from: e.nutrients)
            let mass = max(e.weight_g, 0.0)
            let scale = mass > 0 ? (100.0 / mass) : 0.0
            let baseCal = macros.kcal * scale
            let basePro = macros.pro  * scale
            let baseFat = macros.fat  * scale
            let baseCar = macros.carb * scale

            let comp = MealComponent(
                id: UUID().uuidString,
                name: e.name,
                mass_g: mass,
                base_calories_per_100g: baseCal,
                base_protein_per_100g:  basePro,
                base_fat_per_100g:      baseFat,
                base_carbs_per_100g:    baseCar
            )
            comps.append(comp)
        }

        let tmp = LocalMealHistoryItem(
            id: UUID(),
            date: Date(),
            thumbnailName: saveThumbnail(thumbnail),
            summary: generateTitle(from: comps),
            calories: comps.reduce(0) { $0 + $1.calories_kcal },
            protein:  comps.reduce(0) { $0 + $1.protein_g },
            fat:      comps.reduce(0) { $0 + $1.fat_g },
            carbs:    comps.reduce(0) { $0 + $1.carbs_g },
            rawResult: MealResult(meal: comps)
        )
        return tmp
    }
}
