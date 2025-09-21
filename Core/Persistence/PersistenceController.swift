import Combine
import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let schema = Schema([
        AppUser.self,
        Account.self,
        Merchant.self,
        Transaction.self,
        InventoryItem.self,
        LocationBin.self,
        ShoppingList.self,
        ShoppingListLine.self,
        Habit.self,
        TaskLink.self,
        CalendarLink.self,
        Attachment.self,
        PersonLink.self,
        RuleSpec.self,
        EventRecord.self,
    ])

    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeAttachmentsDirectory(inMemory: Bool = false) throws -> URL {
        let fileManager = FileManager.default
        if inMemory {
            let directory = fileManager.temporaryDirectory.appendingPathComponent(
                "Attachments-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appendingPathComponent("ApplicationSupport", isDirectory: true)
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        var attachmentsDirectory = supportDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try attachmentsDirectory.setResourceValues(resourceValues)
        return attachmentsDirectory
    }

    let modelContainer: ModelContainer
    let mainContext: ModelContext
    let backgroundContext: ModelContext
    let attachmentsDirectory: URL
    let eventStore: EventStore

    let appUsers: ModelRepository<AppUser>
    let accounts: ModelRepository<Account>
    let merchants: ModelRepository<Merchant>
    let transactions: ModelRepository<Transaction>
    let inventoryItems: ModelRepository<InventoryItem>
    let locationBins: ModelRepository<LocationBin>
    let shoppingLists: ModelRepository<ShoppingList>
    let shoppingListLines: ModelRepository<ShoppingListLine>
    let habits: ModelRepository<Habit>
    let taskLinks: ModelRepository<TaskLink>
    let calendarLinks: ModelRepository<CalendarLink>
    let attachments: ModelRepository<Attachment>
    let personLinks: ModelRepository<PersonLink>
    let ruleSpecs: ModelRepository<RuleSpec>
    let eventRecords: ModelRepository<EventRecord>

    init(modelContainer: ModelContainer, attachmentsDirectory: URL) throws {
        self.modelContainer = modelContainer
        self.mainContext = modelContainer.mainContext
        self.backgroundContext = ModelContext(modelContainer)
        self.backgroundContext.autosaveEnabled = false

        self.attachmentsDirectory = attachmentsDirectory
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        self.eventStore = EventStore(container: modelContainer)

        self.appUsers = ModelRepository(context: mainContext)
        self.accounts = ModelRepository(context: mainContext)
        self.merchants = ModelRepository(context: mainContext)
        self.transactions = ModelRepository(context: mainContext)
        self.inventoryItems = ModelRepository(context: mainContext)
        self.locationBins = ModelRepository(context: mainContext)
        self.shoppingLists = ModelRepository(context: mainContext)
        self.shoppingListLines = ModelRepository(context: mainContext)
        self.habits = ModelRepository(context: mainContext)
        self.taskLinks = ModelRepository(context: mainContext)
        self.calendarLinks = ModelRepository(context: mainContext)
        self.attachments = ModelRepository(context: mainContext)
        self.personLinks = ModelRepository(context: mainContext)
        self.ruleSpecs = ModelRepository(context: mainContext)
        self.eventRecords = ModelRepository(context: mainContext)
    }

    convenience init(inMemory: Bool = false) throws {
        let container = try Self.makeModelContainer(inMemory: inMemory)
        let attachmentsDirectory = try Self.makeAttachmentsDirectory(inMemory: inMemory)
        try self.init(modelContainer: container, attachmentsDirectory: attachmentsDirectory)
    }

    func newBackgroundContext() -> ModelContext {
        ModelContext(modelContainer)
    }

    func save(context: ModelContext? = nil) throws {
        let contextToSave = context ?? mainContext
        if contextToSave.hasChanges {
            try contextToSave.save()
        }
    }

    func bootstrapDefaults() async {
        do {
            let descriptor = FetchDescriptor<AppUser>()
            let users = try mainContext.fetch(descriptor)
            if users.isEmpty {
                let user = AppUser()
                mainContext.insert(user)
                try mainContext.save()
            }
        } catch {
            assertionFailure("Failed to bootstrap defaults: \(error)")
        }
    }

    func attachmentURL(for id: UUID = UUID(), fileExtension: String? = nil) -> URL {
        var url = attachmentsDirectory.appendingPathComponent(id.uuidString, isDirectory: false)
        if let fileExtension {
            url = url.appendingPathExtension(fileExtension)
        }
        return url
    }

    @discardableResult
    func storeAttachment(data: Data, id: UUID = UUID(), fileExtension: String? = nil) throws -> URL {
        let destination = attachmentURL(for: id, fileExtension: fileExtension)
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    @discardableResult
    func importAttachment(from sourceURL: URL, id: UUID = UUID(), fileExtension: String? = nil) throws -> URL {
        let destination = attachmentURL(for: id, fileExtension: fileExtension ?? sourceURL.pathExtension)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func removeAttachment(at url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func rebuildDerivedState() async throws {
        let summary: [String: Any] = [
            "accounts": try accounts.count(),
            "transactions": try transactions.count(),
            "inventoryItems": try inventoryItems.count(),
            "shoppingLists": try shoppingLists.count(),
            "habits": try habits.count(),
            "rules": try ruleSpecs.count(),
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: summary, options: [])
        let payload = String(data: payloadData, encoding: .utf8) ?? "{}"
        _ = try eventStore.append(kind: "system.derivedState.rebuilt", payloadJSON: payload)
    }
}

@MainActor
struct ModelRepository<Model: PersistentModel> {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetch(
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = []
    ) throws -> [Model] {
        let descriptor = FetchDescriptor<Model>(predicate: predicate, sortBy: sortBy)
        return try context.fetch(descriptor)
    }

    func first(where predicate: Predicate<Model>) throws -> Model? {
        var descriptor = FetchDescriptor<Model>(predicate: predicate, sortBy: [])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func create(_ builder: () throws -> Model) throws -> Model {
        let model = try builder()
        context.insert(model)
        try context.save()
        return model
    }

    func insert(_ model: Model) throws {
        context.insert(model)
        try context.save()
    }

    func delete(_ model: Model) throws {
        context.delete(model)
        try context.save()
    }

    func delete(predicate: Predicate<Model>) throws -> Int {
        let models = try fetch(predicate: predicate)
        models.forEach { context.delete($0) }
        if !models.isEmpty {
            try context.save()
        }
        return models.count
    }

    func performAndSave(_ work: () throws -> Void) throws {
        try work()
        if context.hasChanges {
            try context.save()
        }
    }

    func count(predicate: Predicate<Model>? = nil) throws -> Int {
        if #available(iOS 17, macOS 14, *) {
            let descriptor = FetchDescriptor<Model>(predicate: predicate, sortBy: [])
            return try context.fetchCount(descriptor)
        } else {
            return try fetch(predicate: predicate).count
        }
    }
}

final class EventStore {
    private let container: ModelContainer
    private let subject = PassthroughSubject<EventRecord, Never>()

    var events: AnyPublisher<EventRecord, Never> {
        subject.eraseToAnyPublisher()
    }

    init(container: ModelContainer) {
        self.container = container
    }

    @discardableResult
    func append(
        kind: String,
        payloadJSON: String,
        occurredAt: Date = .now,
        relatedIds: [UUID] = []
    ) throws -> EventRecord {
        let context = ModelContext(container)
        let record = try EventRecord(
            kind: kind,
            payloadJSON: payloadJSON,
            occurredAt: occurredAt,
            relatedIds: relatedIds
        )
        context.insert(record)
        try context.save()
        subject.send(record)
        return record
    }

    func fetch(
        predicate: Predicate<EventRecord>? = nil,
        sortBy: [SortDescriptor<EventRecord>] = [SortDescriptor(\.occurredAt, order: .forward)]
    ) throws -> [EventRecord] {
        let descriptor = FetchDescriptor<EventRecord>(predicate: predicate, sortBy: sortBy)
        let context = ModelContext(container)
        return try context.fetch(descriptor)
    }
}

@MainActor
struct RebuildDerivedStateCommand {
    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func callAsFunction() async throws {
        try await persistence.rebuildDerivedState()
    }
}
