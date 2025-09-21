import CloudKit
import CryptoKit
import Foundation
import SwiftData

actor SyncService {
    private struct AnySyncAdapter {
        let entity: SyncEntity
        let feature: SyncFeature
        let fetchLocal: @MainActor (PersistenceController) throws -> [SyncPayload]
        let applyRemote: @MainActor (PersistenceController, SyncPayload) throws -> Void
        let deleteLocal: @MainActor (PersistenceController, UUID) throws -> Void
    }

    private enum DefaultsKey {
        static let configuration = "SyncService.Configuration"

        static func changeTokenKey(for entity: SyncEntity) -> String {
            "SyncService.ChangeToken.\(entity.rawValue)"
        }

        static func metadataKey(for entity: SyncEntity) -> String {
            "SyncService.Metadata.\(entity.rawValue)"
        }
    }

    private let persistence: PersistenceController
    private let database: CKDatabase?
    private let defaults: UserDefaults
    private var configuration: SyncConfiguration
    private var status: SyncStatus
    private var changeTokens: [SyncEntity: CKServerChangeToken]
    private var recordMetadata: [SyncEntity: [UUID: SyncRecordMetadata]]
    private var isSyncing = false
    private var statusObservers: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private var configurationObservers: [UUID: AsyncStream<SyncConfiguration>.Continuation] = [:]

    private static let adapters: [SyncEntity: AnySyncAdapter] = {
        var adapters: [SyncEntity: AnySyncAdapter] = [:]

        adapters[.appUser] = AnySyncAdapter(
            entity: .appUser,
            feature: .core,
            fetchLocal: { persistence in
                let models = try persistence.appUsers.fetch()
                return try models.map { model in
                    let snapshot = AppUserSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.identifier, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(AppUserSnapshot.self, from: payload.data)
                if let existing = try persistence.appUsers.first(where: #Predicate { $0.identifier == snapshot.identifier }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let user = snapshot.makeModel()
                    persistence.mainContext.insert(user)
                    try persistence.save()
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.appUsers.delete(predicate: #Predicate { $0.identifier == identifier })
            }
        )

        adapters[.account] = AnySyncAdapter(
            entity: .account,
            feature: .finances,
            fetchLocal: { persistence in
                let models = try persistence.accounts.fetch()
                return try models.map { model in
                    let snapshot = AccountSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(AccountSnapshot.self, from: payload.data)
                if let existing = try persistence.accounts.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let account = try snapshot.makeModel()
                    try persistence.accounts.insert(account)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.accounts.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.merchant] = AnySyncAdapter(
            entity: .merchant,
            feature: .merchants,
            fetchLocal: { persistence in
                let models = try persistence.merchants.fetch()
                return try models.map { model in
                    let snapshot = MerchantSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(MerchantSnapshot.self, from: payload.data)
                if let existing = try persistence.merchants.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let merchant = try snapshot.makeModel()
                    try persistence.merchants.insert(merchant)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.merchants.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.transaction] = AnySyncAdapter(
            entity: .transaction,
            feature: .transactions,
            fetchLocal: { persistence in
                let models = try persistence.transactions.fetch()
                return try models.map { model in
                    let snapshot = TransactionSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(TransactionSnapshot.self, from: payload.data)
                if let existing = try persistence.transactions.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let transaction = try snapshot.makeModel()
                    try persistence.transactions.insert(transaction)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.transactions.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.inventoryItem] = AnySyncAdapter(
            entity: .inventoryItem,
            feature: .inventory,
            fetchLocal: { persistence in
                let models = try persistence.inventoryItems.fetch()
                return try models.map { model in
                    let snapshot = InventoryItemSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(InventoryItemSnapshot.self, from: payload.data)
                if let existing = try persistence.inventoryItems.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let item = try snapshot.makeModel()
                    try persistence.inventoryItems.insert(item)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.inventoryItems.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.locationBin] = AnySyncAdapter(
            entity: .locationBin,
            feature: .inventory,
            fetchLocal: { persistence in
                let models = try persistence.locationBins.fetch()
                return try models.map { model in
                    let snapshot = LocationBinSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(LocationBinSnapshot.self, from: payload.data)
                if let existing = try persistence.locationBins.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let location = try snapshot.makeModel()
                    try persistence.locationBins.insert(location)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.locationBins.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.shoppingList] = AnySyncAdapter(
            entity: .shoppingList,
            feature: .shopping,
            fetchLocal: { persistence in
                let models = try persistence.shoppingLists.fetch()
                return try models.map { model in
                    let snapshot = ShoppingListSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(ShoppingListSnapshot.self, from: payload.data)
                if let existing = try persistence.shoppingLists.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let list = try snapshot.makeModel()
                    try persistence.shoppingLists.insert(list)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.shoppingLists.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.shoppingListLine] = AnySyncAdapter(
            entity: .shoppingListLine,
            feature: .shopping,
            fetchLocal: { persistence in
                let models = try persistence.shoppingListLines.fetch()
                return try models.map { model in
                    let snapshot = ShoppingListLineSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(ShoppingListLineSnapshot.self, from: payload.data)
                let list: ShoppingList?
                if let listId = snapshot.listId {
                    list = try persistence.shoppingLists.first(where: #Predicate { $0.id == listId })
                } else {
                    list = nil
                }
                if let existing = try persistence.shoppingListLines.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing, list: list)
                    try persistence.save()
                } else {
                    let line = try snapshot.makeModel(list: list)
                    try persistence.shoppingListLines.insert(line)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.shoppingListLines.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.habit] = AnySyncAdapter(
            entity: .habit,
            feature: .habits,
            fetchLocal: { persistence in
                let models = try persistence.habits.fetch()
                return try models.map { model in
                    let snapshot = HabitSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(HabitSnapshot.self, from: payload.data)
                if let existing = try persistence.habits.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let habit = try snapshot.makeModel()
                    try persistence.habits.insert(habit)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.habits.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.taskLink] = AnySyncAdapter(
            entity: .taskLink,
            feature: .habits,
            fetchLocal: { persistence in
                let models = try persistence.taskLinks.fetch()
                return try models.map { model in
                    let snapshot = TaskLinkSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(TaskLinkSnapshot.self, from: payload.data)
                if let existing = try persistence.taskLinks.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let link = try snapshot.makeModel()
                    try persistence.taskLinks.insert(link)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.taskLinks.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.calendarLink] = AnySyncAdapter(
            entity: .calendarLink,
            feature: .habits,
            fetchLocal: { persistence in
                let models = try persistence.calendarLinks.fetch()
                return try models.map { model in
                    let snapshot = CalendarLinkSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(CalendarLinkSnapshot.self, from: payload.data)
                if let existing = try persistence.calendarLinks.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let link = try snapshot.makeModel()
                    try persistence.calendarLinks.insert(link)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.calendarLinks.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.attachment] = AnySyncAdapter(
            entity: .attachment,
            feature: .attachments,
            fetchLocal: { persistence in
                let models = try persistence.attachments.fetch()
                return try models.map { model in
                    let snapshot = AttachmentSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(AttachmentSnapshot.self, from: payload.data)
                if let existing = try persistence.attachments.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let attachment = try snapshot.makeModel()
                    try persistence.attachments.insert(attachment)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.attachments.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.budgetEnvelope] = AnySyncAdapter(
            entity: .budgetEnvelope,
            feature: .finances,
            fetchLocal: { persistence in
                let models = try persistence.budgetEnvelopes.fetch()
                return try models.map { model in
                    let snapshot = BudgetEnvelopeSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(BudgetEnvelopeSnapshot.self, from: payload.data)
                if let existing = try persistence.budgetEnvelopes.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let envelope = try snapshot.makeModel()
                    try persistence.budgetEnvelopes.insert(envelope)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.budgetEnvelopes.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.personLink] = AnySyncAdapter(
            entity: .personLink,
            feature: .core,
            fetchLocal: { persistence in
                let models = try persistence.personLinks.fetch()
                return try models.map { model in
                    let snapshot = PersonLinkSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(PersonLinkSnapshot.self, from: payload.data)
                if let existing = try persistence.personLinks.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let link = try snapshot.makeModel()
                    try persistence.personLinks.insert(link)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.personLinks.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.ruleSpec] = AnySyncAdapter(
            entity: .ruleSpec,
            feature: .rules,
            fetchLocal: { persistence in
                let models = try persistence.ruleSpecs.fetch()
                return try models.map { model in
                    let snapshot = RuleSpecSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(RuleSpecSnapshot.self, from: payload.data)
                if let existing = try persistence.ruleSpecs.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let rule = try snapshot.makeModel()
                    try persistence.ruleSpecs.insert(rule)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.ruleSpecs.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        adapters[.eventRecord] = AnySyncAdapter(
            entity: .eventRecord,
            feature: .events,
            fetchLocal: { persistence in
                let models = try persistence.eventRecords.fetch()
                return try models.map { model in
                    let snapshot = EventRecordSnapshot(model: model)
                    let data = try JSONEncoder().encode(snapshot)
                    return SyncPayload(id: snapshot.id, data: data, checksum: checksum(for: data))
                }
            },
            applyRemote: { persistence, payload in
                let snapshot = try JSONDecoder().decode(EventRecordSnapshot.self, from: payload.data)
                if let existing = try persistence.eventRecords.first(where: #Predicate { $0.id == snapshot.id }) {
                    snapshot.apply(to: existing)
                    try persistence.save()
                } else {
                    let record = try snapshot.makeModel()
                    try persistence.eventRecords.insert(record)
                }
            },
            deleteLocal: { persistence, identifier in
                _ = try persistence.eventRecords.delete(predicate: #Predicate { $0.id == identifier })
            }
        )

        return adapters
    }()

    init(
        persistence: PersistenceController,
        container: CKContainer = .default(),
        defaults: UserDefaults = .standard,
        isCloudKitEnabled: Bool = true
    ) {
        self.persistence = persistence
        self.database = isCloudKitEnabled ? container.privateCloudDatabase : nil
        self.defaults = defaults
        self.configuration = Self.loadConfiguration(from: defaults)
        if configuration.isEnabled {
            self.status = .idle(lastSync: nil)
        } else {
            self.status = .disabled
        }
        self.changeTokens = [:]
        self.recordMetadata = [:]
        self.loadPersistedTokens()
        self.loadPersistedMetadata()
    }

    func configurationStream() -> AsyncStream<SyncConfiguration> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(configuration)
            continuation.onTermination = { _ in
                Task { await self.removeConfigurationObserver(id) }
            }
            configurationObservers[id] = continuation
        }
    }

    func statusStream() -> AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(status)
            continuation.onTermination = { _ in
                Task { await self.removeStatusObserver(id) }
            }
            statusObservers[id] = continuation
        }
    }

    func currentConfiguration() -> SyncConfiguration {
        configuration
    }

    func currentStatus() -> SyncStatus {
        status
    }

    func setSyncEnabled(_ isEnabled: Bool) async {
        configuration.setEnabled(isEnabled)
        persistConfiguration()
        if isEnabled {
            await updateStatus(.idle(lastSync: status.lastSyncDate))
        } else {
            await updateStatus(.disabled)
        }
        broadcastConfiguration()
    }

    func setFeature(_ feature: SyncFeature, enabled: Bool) async {
        configuration.setFeature(feature, enabled: enabled)
        persistConfiguration()
        broadcastConfiguration()
    }

    func synchronize() async {
        guard configuration.isEnabled else {
            await updateStatus(.disabled)
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        await updateStatus(.syncing)
        let adapters = activeAdapters()
        do {
            try await ensureZones(for: adapters)
            try await pushLocalChanges(using: adapters)
            try await fetchRemoteChanges(using: adapters)
            let now = Date()
            await updateStatus(.idle(lastSync: now))
        } catch {
            await updateStatus(.error(message: error.localizedDescription, lastSync: status.lastSyncDate))
        }
        isSyncing = false
    }

    // MARK: - Persistence Helpers

    private func activeAdapters() -> [AnySyncAdapter] {
        Self.adapters.values.filter { configuration.allows($0.feature) }
    }

    private func loadPersistedTokens() {
        for entity in SyncEntity.allCases {
            let key = DefaultsKey.changeTokenKey(for: entity)
            guard let data = defaults.data(forKey: key) else { continue }
            if let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) {
                changeTokens[entity] = token
            }
        }
    }

    private func loadPersistedMetadata() {
        let decoder = JSONDecoder()
        for entity in SyncEntity.allCases {
            let key = DefaultsKey.metadataKey(for: entity)
            guard let data = defaults.data(forKey: key) else { continue }
            if let raw = try? decoder.decode([String: SyncRecordMetadata].self, from: data) {
                let mapped = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                    guard let id = UUID(uuidString: key) else { return nil }
                    return (id, value)
                })
                recordMetadata[entity] = mapped
            }
        }
    }

    private func persistConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: DefaultsKey.configuration)
        }
    }

    private func persistChangeToken(_ token: CKServerChangeToken?, for entity: SyncEntity) {
        let key = DefaultsKey.changeTokenKey(for: entity)
        guard let token else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        }
    }

    private func persistMetadata(for entity: SyncEntity) {
        let key = DefaultsKey.metadataKey(for: entity)
        guard let metadata = recordMetadata[entity], !metadata.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        let raw = Dictionary(uniqueKeysWithValues: metadata.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: key)
        }
    }

    private func removeStatusObserver(_ id: UUID) {
        statusObservers[id] = nil
    }

    private func removeConfigurationObserver(_ id: UUID) {
        configurationObservers[id] = nil
    }

    private func broadcastConfiguration() {
        for continuation in configurationObservers.values {
            continuation.yield(configuration)
        }
    }

    private func updateStatus(_ newStatus: SyncStatus) async {
        status = newStatus
        for continuation in statusObservers.values {
            continuation.yield(newStatus)
        }
    }

    private static func loadConfiguration(from defaults: UserDefaults) -> SyncConfiguration {
        if let data = defaults.data(forKey: DefaultsKey.configuration),
           let configuration = try? JSONDecoder().decode(SyncConfiguration.self, from: data) {
            return configuration
        }
        return SyncConfiguration()
    }

    // MARK: - CloudKit Operations

    private func ensureZones(for adapters: [AnySyncAdapter]) async throws {
        guard let database else { return }
        let zones = adapters.map { CKRecordZone(zoneID: $0.entity.zoneID) }
        guard !zones.isEmpty else { return }
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: zones, recordZoneIDsToDelete: nil)
            operation.modifyRecordZonesResultBlock = { result in
                continuation.resume(with: result)
            }
            operation.qualityOfService = .utility
            operation.configuration.isLongLived = true
            database.add(operation)
        }
    }

    private func pushLocalChanges(using adapters: [AnySyncAdapter]) async throws {
        guard !adapters.isEmpty else { return }
        let payloads = try await collectLocalPayloads(adapters: adapters)
        guard let database else {
            let now = Date()
            for (entity, payloadList) in payloads {
                var metadata = recordMetadata[entity, default: [:]]
                for payload in payloadList {
                    metadata[payload.id] = SyncRecordMetadata(checksum: payload.checksum, lastSynced: now)
                }
                recordMetadata[entity] = metadata
                persistMetadata(for: entity)
            }
            return
        }

        var recordsToSave: [CKRecord] = []
        var recordsToDelete: [CKRecord.ID] = []

        for adapter in adapters {
            let entityPayloads = payloads[adapter.entity] ?? []
            let metadata = recordMetadata[adapter.entity] ?? [:]
            let payloadIDs = Set(entityPayloads.map { $0.id })
            let knownIDs = Set(metadata.keys)
            let removed = knownIDs.subtracting(payloadIDs)
            for id in removed {
                recordsToDelete.append(CKRecord.ID(recordName: id.uuidString, zoneID: adapter.entity.zoneID))
            }
            for payload in entityPayloads {
                let existing = metadata[payload.id]
                if existing?.checksum == payload.checksum { continue }
                let recordID = CKRecord.ID(recordName: payload.id.uuidString, zoneID: adapter.entity.zoneID)
                let record = CKRecord(recordType: adapter.entity.recordType, recordID: recordID)
                record["payload"] = payload.data as CKRecordValue
                record["checksum"] = payload.checksum as CKRecordValue
                record["modifiedAt"] = Date() as CKRecordValue
                record["feature"] = adapter.feature.rawValue as CKRecordValue
                recordsToSave.append(record)
            }
        }

        guard !recordsToSave.isEmpty || !recordsToDelete.isEmpty else { return }

        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordsToDelete)
            operation.savePolicy = .allKeys
            operation.isAtomic = false
            operation.configuration.isLongLived = true
            operation.qualityOfService = .utility
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
            }
            database.add(operation)
        }

        let now = Date()
        for adapter in adapters {
            var metadata = recordMetadata[adapter.entity, default: [:]]
            let entityPayloads = payloads[adapter.entity] ?? []
            let payloadMap = Dictionary(uniqueKeysWithValues: entityPayloads.map { ($0.id, $0) })
            let payloadIDs = Set(entityPayloads.map { $0.id })
            for id in payloadIDs {
                if let payload = payloadMap[id] {
                    metadata[id] = SyncRecordMetadata(checksum: payload.checksum, lastSynced: now)
                }
            }
            let knownIDs = Set(metadata.keys)
            let removed = knownIDs.subtracting(payloadIDs)
            for id in removed {
                metadata.removeValue(forKey: id)
            }
            recordMetadata[adapter.entity] = metadata
            persistMetadata(for: adapter.entity)
        }
    }

    private func fetchRemoteChanges(using adapters: [AnySyncAdapter]) async throws {
        guard let database else { return }
        let zoneIDs = adapters.map { $0.entity.zoneID }
        guard !zoneIDs.isEmpty else { return }

        var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for adapter in adapters {
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: changeTokens[adapter.entity])
            configurations[adapter.entity.zoneID] = configuration
        }

        let adapterMap = Dictionary(uniqueKeysWithValues: adapters.map { ($0.entity.zoneID, $0) })
        let lock = NSLock()
        var changed: [(AnySyncAdapter, SyncPayload, Date?)] = []
        var deleted: [(AnySyncAdapter, UUID)] = []

        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, configurationsByRecordZoneID: configurations)
            operation.recordChangedBlock = { record in
                guard let adapter = adapterMap[record.recordID.zoneID],
                      let data = record["payload"] as? Data,
                      let checksum = record["checksum"] as? String,
                      let uuid = UUID(uuidString: record.recordID.recordName) else { return }
                let payload = SyncPayload(id: uuid, data: data, checksum: checksum)
                lock.lock()
                changed.append((adapter, payload, record.modificationDate))
                lock.unlock()
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                guard let adapter = adapterMap[recordID.zoneID],
                      let uuid = UUID(uuidString: recordID.recordName) else { return }
                lock.lock()
                deleted.append((adapter, uuid))
                lock.unlock()
            }
            operation.recordZoneChangeTokensUpdatedBlock = { zoneID, token, _, _ in
                guard let entity = adapterMap[zoneID]?.entity, let token else { return }
                Task { await self.storeChangeToken(token, for: entity) }
            }
            operation.recordZoneFetchCompletionBlock = { zoneID, token, _, _, _ in
                if let entity = adapterMap[zoneID]?.entity {
                    Task { await self.storeChangeToken(token, for: entity) }
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                continuation.resume(with: result)
            }
            operation.configuration.isLongLived = true
            operation.qualityOfService = .utility
            database.add(operation)
        }

        for (adapter, payload, modifiedDate) in changed {
            await applyRemoteChange(adapter: adapter, payload: payload, modifiedDate: modifiedDate)
        }
        for (adapter, identifier) in deleted {
            await applyRemoteDeletion(adapter: adapter, identifier: identifier)
        }
    }

    private func applyRemoteChange(adapter: AnySyncAdapter, payload: SyncPayload, modifiedDate: Date?) async {
        let metadata = recordMetadata[adapter.entity] ?? [:]
        if let existing = metadata[payload.id] {
            if existing.checksum == payload.checksum {
                if let modifiedDate, modifiedDate <= existing.lastSynced { return }
            } else if let modifiedDate, modifiedDate <= existing.lastSynced {
                return
            }
        }

        do {
            try await MainActor.run {
                try adapter.applyRemote(persistence, payload)
            }
            let lastSynced = modifiedDate ?? Date()
            var entityMetadata = recordMetadata[adapter.entity, default: [:]]
            entityMetadata[payload.id] = SyncRecordMetadata(checksum: payload.checksum, lastSynced: lastSynced)
            recordMetadata[adapter.entity] = entityMetadata
            persistMetadata(for: adapter.entity)
        } catch {
            await updateStatus(.error(message: error.localizedDescription, lastSync: status.lastSyncDate))
        }
    }

    private func applyRemoteDeletion(adapter: AnySyncAdapter, identifier: UUID) async {
        do {
            try await MainActor.run {
                try adapter.deleteLocal(persistence, identifier)
            }
            var entityMetadata = recordMetadata[adapter.entity] ?? [:]
            entityMetadata.removeValue(forKey: identifier)
            recordMetadata[adapter.entity] = entityMetadata
            persistMetadata(for: adapter.entity)
        } catch {
            await updateStatus(.error(message: error.localizedDescription, lastSync: status.lastSyncDate))
        }
    }

    private func storeChangeToken(_ token: CKServerChangeToken?, for entity: SyncEntity) async {
        if let token {
            changeTokens[entity] = token
        } else {
            changeTokens.removeValue(forKey: entity)
        }
        persistChangeToken(token, for: entity)
    }

    private func collectLocalPayloads(adapters: [AnySyncAdapter]) async throws -> [SyncEntity: [SyncPayload]] {
        var result: [SyncEntity: [SyncPayload]] = [:]
        for adapter in adapters {
            let payloads = try await MainActor.run {
                try adapter.fetchLocal(persistence)
            }
            result[adapter.entity] = payloads
        }
        return result
    }

}

private func checksum(for data: Data) -> String {
    let hash = SHA256.hash(data: data)
    return hash.map { String(format: "%02x", $0) }.joined()
}
