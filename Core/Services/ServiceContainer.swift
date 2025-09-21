import Foundation

struct ServiceContainer {
    let designSystem = DesignSystem()
    let testing = TestingUtilities()
    let persistence: PersistenceController
    let events: EventDispatcher
    let vision: any VisionOCRServicing
    let barcode: any BarcodeServicing
    let location: any LocationServicing
    let csvImporter: any CSVImportServicing
    let budgetPublisher: BudgetPublisher
    let sync: SyncService
    let dataBackup: DataBackupService

    init(
        persistence: PersistenceController,
        eventDispatcher: EventDispatcher,
        vision: any VisionOCRServicing = VisionOCRService(),
        barcode: any BarcodeServicing = BarcodeService(),
        location: any LocationServicing = LocationService(),
        csvImporter: any CSVImportServicing = CSVImportService(),
        syncService: SyncService? = nil
    ) {
        self.persistence = persistence
        self.events = eventDispatcher
        self.vision = vision
        self.barcode = barcode
        self.location = location
        self.csvImporter = csvImporter
        self.budgetPublisher = BudgetPublisher(persistence: persistence)
        if let syncService {
            self.sync = syncService
        } else {
            self.sync = SyncService(persistence: persistence)
        }
        self.dataBackup = DataBackupService(persistence: persistence)
    }
}

extension ServiceContainer {
    static func makePreview() -> ServiceContainer {
        do {
            let persistence = try PersistenceController(inMemory: true)
            let dispatcher = EventDispatcher()
            let defaults = UserDefaults(suiteName: "preview.sync") ?? .standard
            defaults.removePersistentDomain(forName: "preview.sync")
            let sync = SyncService(persistence: persistence, defaults: defaults, isCloudKitEnabled: false)
            let services = ServiceContainer(
                persistence: persistence,
                eventDispatcher: dispatcher,
                syncService: sync
            )
            return services
        } catch {
            fatalError("Failed to build preview services: \(error)")
        }
    }

    static func inboxPreview() -> ServiceContainer {
        let services = makePreview()
        let store = services.persistence.eventStore
        let now = Date()

        let payloads: [[String: Any]] = [
            [
                "title": "Costco Receipt",
                "detail": "Weekly groceries and household items.",
                "source": "camera",
                "suggestions": ["receipt", "note"]
            ],
            [
                "title": "Budget Notes",
                "detail": "Forwarded from Notes app for review.",
                "source": "share",
                "suggestions": ["note", "csv"]
            ],
            [
                "title": "Checking Account Export",
                "detail": "Downloaded from credit union website.",
                "source": "csv",
                "suggestions": ["csv", "receipt"]
            ]
        ]

        for (index, payload) in payloads.enumerated() {
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let json = String(data: data, encoding: .utf8) else {
                continue
            }

            _ = try? store.append(
                kind: DomainEventKind.inboxEnqueued.rawValue,
                payloadJSON: json,
                occurredAt: now.addingTimeInterval(Double(-index) * 2_700)
            )
        }

        return ServiceContainer(
            persistence: services.persistence,
            eventDispatcher: services.events,
            vision: services.vision,
            barcode: services.barcode,
            location: services.location,
            csvImporter: services.csvImporter,
            syncService: services.sync
        )
    }
}
