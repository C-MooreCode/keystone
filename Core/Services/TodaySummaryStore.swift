import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct TodaySummaryStore {
    static let suiteName = "group.com.example.keystone"
    static let storageKey = "today.summary.snapshot"
    static let todaySummaryWidgetKind = "TodaySummaryWidget"
    static let lowStockWidgetKind = "LowStockWidget"

    private let userDefaults: UserDefaults?

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: suiteName)) {
        self.userDefaults = userDefaults
    }

    func load() -> TodaySummarySnapshot? {
        guard let data = userDefaults?.data(forKey: Self.storageKey) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(TodaySummarySnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    func save(_ summary: TodaySummarySnapshot) {
        guard let userDefaults else { return }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(summary)
            userDefaults.set(data, forKey: Self.storageKey)
            userDefaults.synchronize()
        } catch {
            return
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.todaySummaryWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.lowStockWidgetKind)
        #endif
    }
}
