#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

#if canImport(ActivityKit)
@available(iOS 17.0, *)
struct StoreTripActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var totalItems: Int
        var completedItems: Int
        var pendingItems: Int
    }

    var listId: UUID
    var storeName: String
    var title: String
}

@available(iOS 17.0, *)
extension StoreTripActivityAttributes.ContentState {
    var completionProgress: Double {
        guard totalItems > 0 else { return 0 }
        return min(1, max(0, Double(completedItems) / Double(totalItems)))
    }
}

@available(iOS 17.0, *)
struct FocusSessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var habitName: String
        var targetSeconds: Int
        var startDate: Date
        var endDate: Date
    }

    var habitId: UUID
    var title: String
}

@available(iOS 17.0, *)
extension FocusSessionActivityAttributes.ContentState {
    var timerRange: ClosedRange<Date> {
        let adjustedEnd = max(startDate, endDate)
        return startDate...adjustedEnd
    }

    var progress: Double {
        let total = Double(targetSeconds)
        guard total > 0 else { return 0 }
        let elapsed = min(total, max(0, Date().timeIntervalSince(startDate)))
        return min(1, max(0, elapsed / total))
    }
}
#endif
