import Foundation

class HistoryStorage {
    static let shared = HistoryStorage()
    private let key = "meal_history"
    
    func save(_ item: LocalMealHistoryItem) {
        var history = fetch()
        history.insert(item, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func fetch() -> [LocalMealHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LocalMealHistoryItem].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
