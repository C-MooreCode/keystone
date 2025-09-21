import Foundation
import SwiftData

struct PersistenceController {
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func bootstrapDefaults() async {
        // Placeholder for seeding initial data.
    }
}
