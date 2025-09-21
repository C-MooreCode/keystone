import Foundation
import SwiftUI

@Model
final class AppUser {
    @Attribute(.unique) var identifier: UUID
    var createdAt: Date

    init(identifier: UUID = UUID(), createdAt: Date = .now) {
        self.identifier = identifier
        self.createdAt = createdAt
    }
}

struct AppState {
    var selectedTab: Tab = .today

    enum Tab: Hashable {
        case today
        case inbox
        case inventory
        case shopping
        case expenses
        case habits
        case settings
    }
}

extension AppState.Tab {
    var deepLinkIdentifier: String {
        switch self {
        case .today:
            return "today"
        case .inbox:
            return "inbox"
        case .inventory:
            return "inventory"
        case .shopping:
            return "shopping"
        case .expenses:
            return "expenses"
        case .habits:
            return "habits"
        case .settings:
            return "settings"
        }
    }

    init?(deepLinkIdentifier: String) {
        switch deepLinkIdentifier.lowercased() {
        case "today":
            self = .today
        case "inbox":
            self = .inbox
        case "inventory":
            self = .inventory
        case "shopping":
            self = .shopping
        case "expenses":
            self = .expenses
        case "habits":
            self = .habits
        case "settings":
            self = .settings
        default:
            return nil
        }
    }
}
