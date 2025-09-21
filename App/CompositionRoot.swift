import Foundation
import SwiftData

@MainActor
final class CompositionRoot: ObservableObject {
    let modelContainer: ModelContainer
    let appStore: AppStore

    init() {
        let schema = Schema([AppUser.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.modelContainer = try! ModelContainer(for: schema, configurations: [configuration])

        let services = ServiceContainer()
        let persistence = PersistenceController(modelContainer: modelContainer)
        let syncService = SyncService()
        let reducer = AppReducer(services: services, persistence: persistence, syncService: syncService)
        self.appStore = AppStore(initialState: AppState(), reducer: reducer)
    }
}
