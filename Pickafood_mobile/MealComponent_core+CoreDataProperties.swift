import Foundation
import CoreData


extension MealComponent_core {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MealComponent_core> {
        return NSFetchRequest<MealComponent_core>(entityName: "MealComponent_core")
    }

    @NSManaged public var id: String?
    @NSManaged public var name: String?
    @NSManaged public var mass_g: Double
    @NSManaged public var base_calories_per_100g: Double
    @NSManaged public var base_protein_per_100g: Double
    @NSManaged public var base_fat_per_100g: Double
    @NSManaged public var base_carbs_per_100g: Double
    @NSManaged public var parent: MealHistoryItem_core?

}

extension MealComponent_core : Identifiable {

}
