import SwiftUI

@main
struct FoodCalorieApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            DashboardView(context: persistenceController.container.viewContext)
        }
    }
}
