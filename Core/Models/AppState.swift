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
