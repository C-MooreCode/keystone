import Foundation
import SwiftData
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
#if canImport(os)
import os.log
#endif

@MainActor
final class CompositionRoot: ObservableObject {
    let persistence: PersistenceController
    let appStore: AppStore
    let eventDispatcher: EventDispatcher
    let services: ServiceContainer
#if canImport(BackgroundTasks)
    private let backgroundTasks = BackgroundTaskCoordinator()
#endif

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

#if canImport(BackgroundTasks)
        backgroundTasks.configure(with: services)
#endif

        let reducer = AppReducer(services: services, persistence: persistence, syncService: syncService)
        self.appStore = AppStore(initialState: AppState(), reducer: reducer)

        Task {
            await persistence.bootstrapDefaults()
        }
    }
}

#if canImport(BackgroundTasks)
@MainActor
final class BackgroundTaskCoordinator {
    private enum Constants {
        static let refreshIdentifier = "com.ctm.personal.refresh"
        static let ocrIdentifier = "com.ctm.personal.ocr"
        static let defaultRefreshInterval: TimeInterval = 6 * 60 * 60
        static let defaultOCRInterval: TimeInterval = 2 * 60 * 60
        static let retryInterval: TimeInterval = 30 * 60
    }

    private let logger = Logger(subsystem: "com.ctm.personal", category: "BackgroundTasks")
    private var services: ServiceContainer?
    private var summaryStore = TodaySummaryStore()
    private var refreshWorker: PersonalRefreshWorker?
    private var ocrWorker: OCRProcessingWorker?

    func configure(with services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services
        self.refreshWorker = PersonalRefreshWorker(services: services, summaryStore: summaryStore)
        self.ocrWorker = OCRProcessingWorker(services: services)

        registerTasks()
        scheduleRefresh(after: Constants.defaultRefreshInterval)
        scheduleOCR(after: Constants.defaultOCRInterval)
    }

    private func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Constants.refreshIdentifier, using: nil) { [weak self] task in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleRefreshTask(task)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Constants.ocrIdentifier, using: nil) { [weak self] task in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleOCRTask(task)
        }
    }

    private func handleRefreshTask(_ task: BGTask) {
        scheduleRefresh(after: Constants.defaultRefreshInterval)

        guard let processingTask = task as? BGProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }

        guard let refreshWorker else {
            processingTask.setTaskCompleted(success: false)
            return
        }

        let budget = determineBudget()

        let operation = Task.detached(priority: .background) { [weak self, weak processingTask] in
            do {
                try await refreshWorker.perform(budget: budget)
                processingTask?.setTaskCompleted(success: true)
            } catch is CancellationError {
                self?.logger.warning("Refresh task cancelled due to expiration")
                processingTask?.setTaskCompleted(success: false)
            } catch {
                self?.logger.error("Refresh task failed: \(error.localizedDescription, privacy: .public)")
                processingTask?.setTaskCompleted(success: false)
                self?.scheduleRefresh(after: Constants.retryInterval)
            }
        }

        processingTask.expirationHandler = {
            operation.cancel()
        }
    }

    private func handleOCRTask(_ task: BGTask) {
        scheduleOCR(after: Constants.defaultOCRInterval)

        guard let processingTask = task as? BGProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }

        guard let ocrWorker else {
            processingTask.setTaskCompleted(success: false)
            return
        }

        let budget = determineBudget()

        let operation = Task.detached(priority: .background) { [weak self, weak processingTask] in
            do {
                let processed = try await ocrWorker.processPending(budget: budget)
                self?.logger.debug("Processed \(processed) OCR attachments")
                processingTask?.setTaskCompleted(success: true)
            } catch is CancellationError {
                self?.logger.warning("OCR task cancelled due to expiration")
                processingTask?.setTaskCompleted(success: false)
            } catch {
                self?.logger.error("OCR task failed: \(error.localizedDescription, privacy: .public)")
                processingTask?.setTaskCompleted(success: false)
                self?.scheduleOCR(after: Constants.retryInterval)
            }
        }

        processingTask.expirationHandler = {
            operation.cancel()
        }
    }

    private func scheduleRefresh(after interval: TimeInterval) {
        let request = BGProcessingTaskRequest(identifier: Constants.refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled refresh background task")
        } catch {
            logger.error("Failed to schedule refresh task: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleOCR(after interval: TimeInterval) {
        let request = BGProcessingTaskRequest(identifier: Constants.ocrIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled OCR background task")
        } catch {
            logger.error("Failed to schedule OCR task: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func determineBudget() -> BackgroundExecutionBudget {
        var constrained = false

        #if os(iOS) || os(tvOS) || os(watchOS)
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            constrained = true
        }
        #endif

        if #available(iOS 11.0, macOS 10.15, *) {
            let thermal = ProcessInfo.processInfo.thermalState
            constrained = constrained || thermal == .serious || thermal == .critical
        }

        return BackgroundExecutionBudget(isConstrained: constrained)
    }
}

private struct BackgroundExecutionBudget {
    let isConstrained: Bool
}

private struct LowStockComputationResult {
    let summaryItems: [TodaySummarySnapshot.LowStockItem]
    let totalCount: Int
    let tags: Set<String>
    let hasOpenShoppingItems: Bool
}

private struct PersonalRefreshWorker {
    private let services: ServiceContainer
    private let summaryStore: TodaySummaryStore
    private let logger = Logger(subsystem: "com.ctm.personal", category: "BackgroundTasks.Refresh")

    init(services: ServiceContainer, summaryStore: TodaySummaryStore) {
        self.services = services
        self.summaryStore = summaryStore
    }

    func perform(budget: BackgroundExecutionBudget) async throws {
        try Task.checkCancellation()
        let lowStock = try await computeLowStock()
        try Task.checkCancellation()
        await updateSummary(with: lowStock.summaryItems, totalCount: lowStock.totalCount)
        try Task.checkCancellation()

        if budget.isConstrained {
            logger.debug("Skipping rule execution due to constrained budget")
            return
        }

        try await runRulesIfNeeded(lowStock: lowStock)
    }

    private func computeLowStock() async throws -> LowStockComputationResult {
        try await MainActor.run {
            let items = try services.persistence.inventoryItems.fetch()
            var tags = Set<String>()

            let lowItems = items.compactMap { item -> (TodaySummarySnapshot.LowStockItem, [String])? in
                let threshold = NSDecimalNumber(decimal: item.restockThreshold).doubleValue
                guard threshold > 0, item.qty <= threshold else { return nil }
                let snapshot = TodaySummarySnapshot.LowStockItem(
                    id: item.id,
                    name: item.name,
                    quantity: item.qty,
                    threshold: threshold,
                    unit: item.unit
                )
                return (snapshot, item.tags)
            }

            lowItems.forEach { tags.formUnion($0.1.map { $0.lowercased() }) }

            let sorted = lowItems.map(\.0).sorted { lhs, rhs in
                let lhsRatio = lhs.threshold > 0 ? lhs.quantity / lhs.threshold : Double.greatestFiniteMagnitude
                let rhsRatio = rhs.threshold > 0 ? rhs.quantity / rhs.threshold : Double.greatestFiniteMagnitude
                if lhsRatio != rhsRatio {
                    return lhsRatio < rhsRatio
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            let pendingPredicate = #Predicate<ShoppingListLine> { line in
                line.status == "pending"
            }
            let pendingLines = try services.persistence.shoppingListLines.fetch(predicate: pendingPredicate)

            return LowStockComputationResult(
                summaryItems: Array(sorted.prefix(20)),
                totalCount: lowItems.count,
                tags: tags,
                hasOpenShoppingItems: !pendingLines.isEmpty
            )
        }
    }

    private func updateSummary(with items: [TodaySummarySnapshot.LowStockItem], totalCount: Int) async {
        await MainActor.run {
            var snapshot = summaryStore.load() ?? TodaySummarySnapshot()
            snapshot.lowStockItems = items
            snapshot.lowStockCount = totalCount
            snapshot.generatedAt = Date()
            summaryStore.save(snapshot)
        }
    }

    private func runRulesIfNeeded(lowStock: LowStockComputationResult) async throws {
        guard lowStock.totalCount > 0 else { return }

        try await MainActor.run {
            let enabledSpecs = try services.persistence.ruleSpecs.fetch().filter(\.enabled)
            guard !enabledSpecs.isEmpty else { return }

            let codec = RuleSpecCodec()
            let evaluator = RuleEvaluator()
            let guardrail = InMemoryRuleIdempotencyGuard(ttl: 5 * 60)
            let snapshot = RuleSnapshot(
                fields: ["inventory.lowStockCount": .number(Double(lowStock.totalCount))],
                tags: lowStock.tags,
                listHasOpenItems: lowStock.hasOpenShoppingItems
            )

            for spec in enabledSpecs {
                do {
                    let definition = try spec.toRuleDefinition(codec: codec)
                    let actions = evaluator.evaluate(rule: definition, when: .inventoryBelowThreshold, snapshot: snapshot)
                    guard !actions.isEmpty else { continue }
                    guard guardrail.shouldProceed(with: definition.id) else { continue }
                    logger.notice("Executing rule \(definition.name, privacy: .public)")
                    try await perform(actions, for: definition)
                } catch {
                    logger.error("Failed to execute rule: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func perform(_ actions: [RuleAction], for rule: RuleDefinition) async throws {
        for action in actions {
            try Task.checkCancellation()
            switch action {
            case let .notify(message):
                await recordEvent(kind: .ruleFired, rule: rule, extra: ["message": message])
            case .shoppingAddMissingFromLowStock:
                try await addMissingLowStock(rule: rule)
            case let .transactionCreate(fromReceipt):
                await recordEvent(kind: .ruleFired, rule: rule, extra: ["transactionFromReceipt": fromReceipt])
            case let .habitTick(name, amount):
                await recordEvent(kind: .ruleFailed, rule: rule, extra: ["reason": "habitTick not supported", "habit": name, "amount": amount])
            case let .remindersCreate(title, dueISO8601):
                await recordEvent(kind: .ruleFailed, rule: rule, extra: ["reason": "remindersCreate not supported", "title": title, "due": dueISO8601])
            case let .calendarBlock(title, startISO8601, durationMinutes):
                await recordEvent(kind: .ruleFailed, rule: rule, extra: [
                    "reason": "calendarBlock not supported",
                    "title": title,
                    "start": startISO8601,
                    "duration": durationMinutes
                ])
            }
        }
    }

    private func addMissingLowStock(rule: RuleDefinition) async throws {
        do {
            let additions = try await MainActor.run { () -> Int in
                let repository = services.persistence.inventoryItems
                let items = try repository.fetch()
                let lowItems = items.filter { item in
                    let threshold = NSDecimalNumber(decimal: item.restockThreshold).doubleValue
                    return threshold > 0 && item.qty <= threshold
                }

                guard !lowItems.isEmpty else { return 0 }

                let list = try resolveShoppingList()
                var additions = 0

                for item in lowItems {
                    let desired = max(NSDecimalNumber(decimal: item.restockThreshold).doubleValue - item.qty, 1)
                    if let existing = list.lines.first(where: { $0.inventoryItemId == item.id && $0.status == "pending" }) {
                        if existing.desiredQty < desired {
                            try services.persistence.shoppingListLines.performAndSave {
                                existing.desiredQty = desired
                            }
                            additions += 1
                        }
                    } else {
                        _ = try services.persistence.shoppingListLines.create {
                            try ShoppingListLine(
                                inventoryItemId: item.id,
                                name: item.name,
                                desiredQty: desired,
                                status: "pending",
                                preferredMerchantId: nil,
                                list: list
                            )
                        }
                        additions += 1
                    }
                }

                return additions
            }

            if additions > 0 {
                await recordEvent(kind: .ruleFired, rule: rule, extra: ["added": additions])
            }
        } catch {
            logger.error("Failed to merge low stock into shopping: \(error.localizedDescription, privacy: .public)")
            await recordEvent(kind: .ruleFailed, rule: rule, extra: ["reason": error.localizedDescription])
        }
    }

    private func resolveShoppingList() throws -> ShoppingList {
        if let existing = try services.persistence.shoppingLists.first(where: #Predicate { $0.name == "Shopping" }) {
            return existing
        }

        return try services.persistence.shoppingLists.create {
            try ShoppingList(name: "Shopping")
        }
    }

    private func recordEvent(kind: DomainEventKind, rule: RuleDefinition, extra: [String: Any] = [:]) async {
        await MainActor.run {
            var payload: [String: Any] = [
                "ruleId": rule.id.uuidString,
                "ruleName": rule.name
            ]
            extra.forEach { payload[$0.key] = $0.value }

            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let json = String(data: data, encoding: .utf8) else { return }

            do {
                try services.persistence.eventStore.append(
                    kind: kind.rawValue,
                    payloadJSON: json
                )
            } catch {
                logger.error("Failed to record event: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension PersonalRefreshWorker: @unchecked Sendable {}

private struct OCRProcessingWorker {
    private struct AttachmentJob {
        let id: UUID
        let url: URL
    }

    private let services: ServiceContainer
    private let logger = Logger(subsystem: "com.ctm.personal", category: "BackgroundTasks.OCR")

    init(services: ServiceContainer) {
        self.services = services
    }

    func processPending(budget: BackgroundExecutionBudget) async throws -> Int {
        let limit = budget.isConstrained ? 1 : 5
        try Task.checkCancellation()
        let jobs = try await pendingAttachments(limit: limit)
        guard !jobs.isEmpty else { return 0 }

        var processed = 0
        for job in jobs {
            try Task.checkCancellation()
            do {
                if let text = try await extractText(for: job) {
                    try await storeText(text, for: job.id)
                    processed += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("OCR processing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return processed
    }

    private func pendingAttachments(limit: Int) async throws -> [AttachmentJob] {
        try await MainActor.run {
            let attachments = try services.persistence.attachments.fetch().filter { attachment in
                attachment.ocrText?.isEmpty ?? true
            }
            return attachments.prefix(limit).map { AttachmentJob(id: $0.id, url: $0.localURL) }
        }
    }

    private func extractText(for job: AttachmentJob) async throws -> String? {
        let didAccess = job.url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                job.url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try await services.vision.scan(at: job.url)
            return render(result: result)
        } catch let error as VisionOCRError {
            switch error {
            case .unsupportedPlatform:
                logger.warning("OCR unsupported on this platform")
                return nil
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    private func render(result: VisionOCRResult) -> String {
        var components: [String] = []
        if let merchant = result.merchant.value {
            components.append("Merchant: \(merchant)")
        }
        if let date = result.date.value {
            let formatter = ISO8601DateFormatter()
            components.append("Date: \(formatter.string(from: date))")
        }
        if let total = result.total.value {
            components.append("Total: \(NSDecimalNumber(decimal: total).stringValue)")
        }

        if !result.lineItems.isEmpty {
            components.append("Items:")
            for item in result.lineItems {
                let name = item.name.value ?? "Item"
                let quantity = item.quantity.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "1"
                let price = item.price.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                let detail = price.isEmpty ? "" : " @ \(price)"
                components.append("- \(name) x\(quantity)\(detail)")
            }
        }

        return components.joined(separator: "\n")
    }

    private func storeText(_ text: String, for id: UUID) async throws {
        try await MainActor.run {
            guard let attachment = try services.persistence.attachments.first(where: #Predicate { $0.id == id }) else {
                return
            }

            try services.persistence.attachments.performAndSave {
                attachment.ocrText = text
            }
        }
    }
}

extension OCRProcessingWorker: @unchecked Sendable {}
#endif
