import Foundation

struct ServiceContainer {
    let designSystem = DesignSystem()
    let testing = TestingUtilities()
    let persistence: PersistenceController
    let events: EventDispatcher

    init(persistence: PersistenceController, eventDispatcher: EventDispatcher) {
        self.persistence = persistence
        self.events = eventDispatcher
    }
}
