import CoreData

extension LocalMealHistoryItem {
    init(from core: MealHistoryItem_core) {
        self.id = core.id ?? UUID()
        self.date = core.date ?? Date()
        self.thumbnailName = core.thumbnailName
        self.summary = core.summary ?? ""
        self.calories = core.calories
        self.protein = core.protein
        self.fat = core.fat
        self.carbs = core.carbs
        // Mapuj składniki (relacja mealComponents)
        let comps = (core.mealComponents?.allObjects as? [MealComponent_core] ?? []).map { MealComponent(from: $0) }
        self.rawResult = MealResult(meal: comps)
    }
}

extension MealComponent {
    init(from core: MealComponent_core) {
        self.id = core.id ?? UUID().uuidString
        self.name = core.name ?? ""
        self.mass_g = core.mass_g
        self.base_calories_per_100g = core.base_calories_per_100g
        self.base_protein_per_100g = core.base_protein_per_100g
        self.base_fat_per_100g = core.base_fat_per_100g
        self.base_carbs_per_100g = core.base_carbs_per_100g
    }
}

extension MealHistoryItem_core {
    func update(from local: LocalMealHistoryItem, context: NSManagedObjectContext) {
        self.id = local.id
        self.date = local.date
        self.thumbnailName = local.thumbnailName
        self.summary = local.summary
        self.calories = local.calories
        self.protein = local.protein
        self.fat = local.fat
        self.carbs = local.carbs

        if let comps = self.mealComponents as? Set<MealComponent_core> {
            comps.forEach { context.delete($0) }
        }
        
        let newComponents: [MealComponent_core] = local.rawResult.meal.map { mc in
            let comp = MealComponent_core(context: context)
            comp.update(from: mc)
            comp.parent = self
            return comp
        }
        self.mealComponents = NSSet(array: newComponents)
    }
}

extension MealComponent_core {
    func update(from local: MealComponent) {
        self.id = local.id
        self.name = local.name
        self.mass_g = local.mass_g
        self.base_calories_per_100g = local.base_calories_per_100g
        self.base_protein_per_100g = local.base_protein_per_100g
        self.base_fat_per_100g = local.base_fat_per_100g
        self.base_carbs_per_100g = local.base_carbs_per_100g
    }
}


