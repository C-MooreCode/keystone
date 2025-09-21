import Foundation

@MainActor
enum IntentDependencyContainer {
    static let shared: IntentDependencyContainerImplementation = {
        IntentDependencyContainerImplementation()
    }()
}

@MainActor
final class IntentDependencyContainerImplementation {
    let services: ServiceContainer

    init() {
        do {
            let persistence = try PersistenceController()
            let dispatcher = EventDispatcher()
            let syncService = SyncService(persistence: persistence)
            self.services = ServiceContainer(
                persistence: persistence,
                eventDispatcher: dispatcher,
                syncService: syncService
            )
        } catch {
            fatalError("Failed to build intent dependencies: \(error)")
        }
    }
}
