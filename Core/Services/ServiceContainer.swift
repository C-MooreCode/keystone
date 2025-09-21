import Foundation

struct ServiceContainer {
    let designSystem = DesignSystem()
    let testing = TestingUtilities()
    let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }
}
