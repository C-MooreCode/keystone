import Foundation
import SwiftData

@MainActor
final class CompositionRoot: ObservableObject {
    let persistence: PersistenceController
    let appStore: AppStore

    var modelContainer: ModelContainer { persistence.modelContainer }

    init() {
        let persistence: PersistenceController
        do {
            persistence = try PersistenceController()
        } catch {
            fatalError("Failed to initialise persistence: \(error)")
        }
        self.persistence = persistence

        let services = ServiceContainer(persistence: persistence)
        let syncService = SyncService()
        let reducer = AppReducer(services: services, persistence: persistence, syncService: syncService)
        self.appStore = AppStore(initialState: AppState(), reducer: reducer)

        Task {
            await persistence.bootstrapDefaults()
        }
    }
}
