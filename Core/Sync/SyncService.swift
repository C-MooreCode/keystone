import CloudKit
import Foundation
import SwiftData

actor SyncService {

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

    private static let adapters = SyncSnapshotAdapter.all

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

    private func activeAdapters() -> [SyncSnapshotAdapter] {
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

    private func ensureZones(for adapters: [SyncSnapshotAdapter]) async throws {
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

    private func pushLocalChanges(using adapters: [SyncSnapshotAdapter]) async throws {
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

    private func fetchRemoteChanges(using adapters: [SyncSnapshotAdapter]) async throws {
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
        var changed: [(SyncSnapshotAdapter, SyncPayload, Date?)] = []
        var deleted: [(SyncSnapshotAdapter, UUID)] = []

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

    private func applyRemoteChange(adapter: SyncSnapshotAdapter, payload: SyncPayload, modifiedDate: Date?) async {
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

    private func applyRemoteDeletion(adapter: SyncSnapshotAdapter, identifier: UUID) async {
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

    private func collectLocalPayloads(adapters: [SyncSnapshotAdapter]) async throws -> [SyncEntity: [SyncPayload]] {
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
