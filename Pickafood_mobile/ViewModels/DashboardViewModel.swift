import Foundation
import CoreData
import UIKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var history: [LocalMealHistoryItem] = []
    @Published var shouldShowProgress = false
    @Published var currentTaskID: String?
    @Published var startErrorMsg: String?
    @Published var isSubmitting = false
    
    
    let context: NSManagedObjectContext
    init(context: NSManagedObjectContext) {
        self.context = context
        fetchHistory()
    }

    func fetchHistory() {
        let fetchRequest: NSFetchRequest<MealHistoryItem_core> = MealHistoryItem_core.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        do {
            let results = try context.fetch(fetchRequest)
            self.history = results.map { LocalMealHistoryItem(from: $0) }
        } catch {
            print("Błąd pobierania historii z CoreData: \(error)")
            self.history = []
        }
    }

    func update(_ updated: LocalMealHistoryItem) {
        let fetchRequest: NSFetchRequest<MealHistoryItem_core> = MealHistoryItem_core.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", updated.id as CVarArg)
        do {
            if let coreItem = try context.fetch(fetchRequest).first {
                coreItem.summary = updated.summary
                coreItem.date = updated.date
                coreItem.calories = updated.calories
                coreItem.protein = updated.protein
                coreItem.fat = updated.fat
                coreItem.carbs = updated.carbs

                if let comps = coreItem.mealComponents as? Set<MealComponent_core> {
                    comps.forEach { context.delete($0) }
                }
                let newComponents: [MealComponent_core] = updated.rawResult.meal.map { mc in
                    let comp = MealComponent_core(context: context)
                    comp.id = mc.id
                    comp.name = mc.name
                    comp.mass_g = mc.mass_g
                    comp.base_calories_per_100g = mc.base_calories_per_100g
                    comp.base_protein_per_100g = mc.base_protein_per_100g
                    comp.base_fat_per_100g = mc.base_fat_per_100g
                    comp.base_carbs_per_100g = mc.base_carbs_per_100g
                    comp.parent = coreItem
                    return comp
                }
                coreItem.mealComponents = NSSet(array: newComponents)

                try context.save()
                fetchHistory()
            }
        } catch {
            print("Błąd aktualizacji historii: \(error)")
        }
    }
    
    func add(_ newItem: LocalMealHistoryItem) {

        let coreItem              = MealHistoryItem_core(context: context)
        coreItem.id               = newItem.id                // UUID
        coreItem.date             = newItem.date
        coreItem.thumbnailName    = newItem.thumbnailName
        coreItem.summary          = newItem.summary
        coreItem.calories         = newItem.calories
        coreItem.protein          = newItem.protein
        coreItem.fat              = newItem.fat
        coreItem.carbs            = newItem.carbs

        let coreComponents: [MealComponent_core] = newItem.rawResult.meal.map { mc in
            let comp = MealComponent_core(context: context)
            comp.update(from: mc)
            comp.parent = coreItem
            return comp
        }
        coreItem.mealComponents = NSSet(array: coreComponents)

        do {
            try context.save()
            fetchHistory()
        } catch {
            print("Błąd zapisu nowego wpisu: \(error)")
        }
    }
    
    func delete(_ meal: LocalMealHistoryItem) {
        let fetch: NSFetchRequest<MealHistoryItem_core> = MealHistoryItem_core.fetchRequest()
        fetch.predicate = NSPredicate(format: "id == %@", meal.id as CVarArg)
        do {
            if let coreItem = try context.fetch(fetch).first {
                context.delete(coreItem)
                try context.save()
                fetchHistory()
            }
        } catch {
            print("Błąd usuwania wpisu: \(error)")
        }
    }
    
    func startAnalysis(with payload: CapturePayload) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer {
            if !shouldShowProgress { isSubmitting = false }
        }
        do {
            let taskID = try await APIClient.shared.analyse(
                rgb: payload.image,
                depthURL: payload.depthURL,
                fx: payload.fx, fy: payload.fy, cx: payload.cx, cy: payload.cy
            )
            self.currentTaskID = taskID
            self.shouldShowProgress = true
        } catch {
            _ = try? await PendingDataManager.shared.saveCapture(payload)
            self.startErrorMsg = "Brak połączenia z serwerem. Zapisano ujęcie w danych offline."
        }
    }

       func startAnalysisFromGallery(jpegData: Data, image: UIImage) async {
           let (W, H) = image.pixelSize
           let fx, fy, cx, cy: Double

           if let cached = IntrinsicsCache.shared.lookup(for: jpegData, normalizedSize: image.size) {
               (fx, fy, cx, cy) = cached
           } else if let (fx0, fy0, cx0, cy0) = GalleryIntrinsics.estimate(from: jpegData,
                                                                           imageSize: CGSize(width: W, height: H)) {
               (fx, fy, cx, cy) = (fx0, fy0, cx0, cy0)
           } else {
               (fx, fy, cx, cy) = GalleryIntrinsics.scaleIntrinsics(
                   fx: 3000, fy: 3000,
                   cx: Double(W - 1) / 2.0,
                   cy: Double(H - 1) / 2.0,
                   from: CGSize(width: W, height: H),
                   to:   CGSize(width: W, height: H)
               )
           }

           do {
               let taskID = try await APIClient.shared.analyse(
                   rgb: image,
                   depthURL: nil,
                   fx: fx, fy: fy, cx: cx, cy: cy
               )
               self.currentTaskID = taskID
               self.shouldShowProgress = true
           } catch {
               self.startErrorMsg = "Brak połączenia z serwerem. Spróbuj ponownie później."
           }
       }

}
