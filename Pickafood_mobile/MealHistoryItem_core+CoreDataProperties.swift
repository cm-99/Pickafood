import Foundation
import CoreData


extension MealHistoryItem_core {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MealHistoryItem_core> {
        return NSFetchRequest<MealHistoryItem_core>(entityName: "MealHistoryItem_core")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var thumbnailName: String?
    @NSManaged public var summary: String?
    @NSManaged public var calories: Double
    @NSManaged public var protein: Double
    @NSManaged public var fat: Double
    @NSManaged public var carbs: Double
    @NSManaged public var mealComponents: NSSet?

}

// MARK: Generated accessors for mealComponents
extension MealHistoryItem_core {

    @objc(addMealComponentsObject:)
    @NSManaged public func addToMealComponents(_ value: MealComponent_core)

    @objc(removeMealComponentsObject:)
    @NSManaged public func removeFromMealComponents(_ value: MealComponent_core)

    @objc(addMealComponents:)
    @NSManaged public func addToMealComponents(_ values: NSSet)

    @objc(removeMealComponents:)
    @NSManaged public func removeFromMealComponents(_ values: NSSet)

}

extension MealHistoryItem_core : Identifiable {

}
