import Compression
import Foundation
import SwiftData

enum DataBackupError: LocalizedError {
    case missingDataFile
    case invalidRecord
    case unsupportedEntity(String)
    case missingIdentifier(SyncEntity)

    var errorDescription: String? {
        switch self {
        case .missingDataFile:
            return "The backup archive is missing the data.jsonl file."
        case .invalidRecord:
            return "The backup archive contains a malformed record."
        case let .unsupportedEntity(name):
            return "The backup contains an unknown entity type: \(name)."
        case let .missingIdentifier(entity):
            return "A \(entity.rawValue) record is missing its identifier."
        }
    }
}

final class DataBackupService {
    private let persistence: PersistenceController
    private let fileManager: FileManager
    private let adapters = SyncSnapshotAdapter.all

    init(persistence: PersistenceController, fileManager: FileManager = .default) {
        self.persistence = persistence
        self.fileManager = fileManager
    }

    func prepareExportArchive() async throws -> URL {
        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "KeystoneExport-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let dataURL = workingDirectory.appendingPathComponent("data.jsonl", isDirectory: false)
        let lines = try await exportLines()
        let payload = lines.joined(separator: "\n")
        try payload.write(to: dataURL, atomically: true, encoding: .utf8)

        let attachmentsDestination = workingDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try exportAttachments(to: attachmentsDestination)

        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(
            "Keystone-\(Self.filenameFormatter.string(from: Date())).keystone",
            isDirectory: false
        )
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.zipItem(at: workingDirectory, to: archiveURL, shouldKeepParent: false)
        try fileManager.removeItem(at: workingDirectory)
        return archiveURL
    }

    func importArchive(from archiveURL: URL) async throws {
        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "KeystoneImport-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workingDirectory) }

        try fileManager.unzipItem(at: archiveURL, to: workingDirectory)

        let dataURL = workingDirectory.appendingPathComponent("data.jsonl", isDirectory: false)
        guard fileManager.fileExists(atPath: dataURL.path) else {
            throw DataBackupError.missingDataFile
        }

        let attachmentsSource = workingDirectory.appendingPathComponent("Attachments", isDirectory: true)
        let records = try readRecords(from: dataURL)

        try await MainActor.run {
            try wipeExistingData()
        }

        try await apply(records: records)
        try replaceAttachments(withContentsOf: attachmentsSource)
    }

    // MARK: - Export

    private func exportLines() async throws -> [String] {
        var lines: [String] = []
        for entity in SyncEntity.allCases {
            guard let adapter = adapters[entity] else { continue }
            let payloads = try await MainActor.run {
                try adapter.fetchLocal(persistence)
            }
            for payload in payloads {
                let jsonObject = try JSONSerialization.jsonObject(with: payload.data, options: [])
                let lineObject: [String: Any] = [
                    "entity": entity.rawValue,
                    "payload": jsonObject
                ]
                let lineData = try JSONSerialization.data(withJSONObject: lineObject, options: [.sortedKeys])
                if let line = String(data: lineData, encoding: .utf8) {
                    lines.append(line)
                }
            }
        }
        return lines
    }

    private func exportAttachments(to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if fileManager.fileExists(atPath: persistence.attachmentsDirectory.path) {
            try fileManager.copyItem(at: persistence.attachmentsDirectory, to: destination)
        } else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }
    }

    // MARK: - Import

    private func readRecords(from url: URL) throws -> [SyncEntity: [[String: Any]]] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let lines = raw.split(whereSeparator: \.isNewline)
        var records: [SyncEntity: [[String: Any]]] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dictionary = object as? [String: Any],
                  let entityName = dictionary["entity"] as? String,
                  let payload = dictionary["payload"] else {
                throw DataBackupError.invalidRecord
            }
            guard let entity = SyncEntity(rawValue: entityName) else {
                throw DataBackupError.unsupportedEntity(entityName)
            }
            guard let payloadDictionary = payload as? [String: Any] else {
                throw DataBackupError.invalidRecord
            }
            records[entity, default: []].append(payloadDictionary)
        }
        return records
    }

    private func apply(records: [SyncEntity: [[String: Any]]]) async throws {
        for entity in SyncEntity.allCases {
            guard let adapter = adapters[entity] else { continue }
            let payloads = records[entity] ?? []
            for payload in payloads {
                let (identifier, data) = try preparePayload(for: entity, payload: payload)
                let syncPayload = SyncPayload(id: identifier, data: data, checksum: syncChecksum(for: data))
                try await MainActor.run {
                    try adapter.applyRemote(persistence, syncPayload)
                }
            }
        }
    }

    private func preparePayload(for entity: SyncEntity, payload: [String: Any]) throws -> (UUID, Data) {
        var record = payload
        guard let idString = (record["id"] as? String) ?? (record["identifier"] as? String),
              let identifier = UUID(uuidString: idString) else {
            throw DataBackupError.missingIdentifier(entity)
        }

        if entity == .attachment,
           let urlString = record["localURL"] as? String,
           let originalURL = URL(string: urlString) {
            let fileName = originalURL.lastPathComponent
            let destination = persistence.attachmentsDirectory.appendingPathComponent(fileName, isDirectory: false)
            record["localURL"] = destination.absoluteString
        }

        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return (identifier, data)
    }

    private func replaceAttachments(withContentsOf source: URL) throws {
        let destination = persistence.attachmentsDirectory
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        let existing = try fileManager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        for url in existing {
            try fileManager.removeItem(at: url)
        }

        guard fileManager.fileExists(atPath: source.path) else { return }
        let items = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
        }
    }

    @MainActor
    private func wipeExistingData() throws {
        try deleteAll(EventRecord.self)
        try deleteAll(RuleSpec.self)
        try deleteAll(PersonLink.self)
        try deleteAll(BudgetEnvelope.self)
        try deleteAll(Attachment.self)
        try deleteAll(CalendarLink.self)
        try deleteAll(TaskLink.self)
        try deleteAll(Habit.self)
        try deleteAll(ShoppingListLine.self)
        try deleteAll(ShoppingList.self)
        try deleteAll(LocationBin.self)
        try deleteAll(InventoryItem.self)
        try deleteAll(Transaction.self)
        try deleteAll(Merchant.self)
        try deleteAll(Account.self)
        try deleteAll(AppUser.self)
    }

    @MainActor
    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
        let context = persistence.mainContext
        let descriptor = FetchDescriptor<Model>()
        let models = try context.fetch(descriptor)
        models.forEach { context.delete($0) }
        if context.hasChanges {
            try context.save()
        }
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = .current
        return formatter
    }()
}
