import Foundation
import SwiftData

@MainActor
final class CompositionRoot: ObservableObject {
    let persistence: PersistenceController
    let appStore: AppStore
    let eventDispatcher: EventDispatcher
    let services: ServiceContainer

    var modelContainer: ModelContainer { persistence.modelContainer }

    init() {
        let persistence: PersistenceController
        do {
            persistence = try PersistenceController()
        } catch {
            fatalError("Failed to initialise persistence: \(error)")
        }
        self.persistence = persistence

        let eventDispatcher = EventDispatcher()
        self.eventDispatcher = eventDispatcher

        let syncService = SyncService(persistence: persistence)
        let services = ServiceContainer(
            persistence: persistence,
            eventDispatcher: eventDispatcher,
            syncService: syncService
        )
        self.services = services

        let importer = ShareInboxImporter(persistence: persistence, events: eventDispatcher)
        importer.importPendingItems()

        let reducer = AppReducer(services: services, persistence: persistence, syncService: syncService)
        self.appStore = AppStore(initialState: AppState(), reducer: reducer)

        Task {
            await persistence.bootstrapDefaults()
        }
    }
}
