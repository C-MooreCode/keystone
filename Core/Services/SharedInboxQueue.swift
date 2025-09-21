import Foundation

struct SharedInboxQueue {
    static let appGroupIdentifier = "group.com.example.keystone"
    private static let queueKey = "inbox.queue.pending"
    static let attachmentsDirectoryName = "Inbox/Attachments"

    private let userDefaults: UserDefaults?
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.userDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        self.fileManager = fileManager
    }

    func enqueue(_ item: SharedInboxItem) throws {
        var items = try loadItems()
        items.append(item)
        try persist(items)
    }

    func dequeueAll() -> [SharedInboxItem] {
        guard let userDefaults else { return [] }

        do {
            let items = try loadItems()
            userDefaults.removeObject(forKey: Self.queueKey)
            userDefaults.synchronize()
            return items
        } catch {
            userDefaults.removeObject(forKey: Self.queueKey)
            userDefaults.synchronize()
            return []
        }
    }

    func sharedContainerURL() throws -> URL {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
            throw SharedInboxQueueError.missingAppGroupContainer
        }
        return containerURL
    }

    func attachmentsDirectoryURL() throws -> URL {
        let base = try sharedContainerURL()
        let attachmentsDirectory = base.appendingPathComponent(Self.attachmentsDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: attachmentsDirectory.path) {
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
        return attachmentsDirectory
    }

    // MARK: - Private

    private func loadItems() throws -> [SharedInboxItem] {
        guard let userDefaults else { throw SharedInboxQueueError.unavailableUserDefaults }
        guard let data = userDefaults.data(forKey: Self.queueKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([SharedInboxItem].self, from: data)
        } catch {
            throw SharedInboxQueueError.decodingFailed(error)
        }
    }

    private func persist(_ items: [SharedInboxItem]) throws {
        guard let userDefaults else { throw SharedInboxQueueError.unavailableUserDefaults }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            userDefaults.set(data, forKey: Self.queueKey)
            userDefaults.synchronize()
        } catch {
            throw SharedInboxQueueError.encodingFailed(error)
        }
    }
}

struct SharedInboxItem: Codable, Identifiable {
    let id: UUID
    let title: String?
    let detail: String?
    let receivedAt: Date
    let source: SharedInboxSource
    let suggestions: [SharedInboxSuggestion]
    let attachments: [SharedInboxAttachment]

    init(
        id: UUID = UUID(),
        title: String?,
        detail: String?,
        receivedAt: Date = .now,
        source: SharedInboxSource = .share,
        suggestions: [SharedInboxSuggestion],
        attachments: [SharedInboxAttachment]
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.receivedAt = receivedAt
        self.source = source
        self.suggestions = suggestions
        self.attachments = attachments
    }

    var relatedAttachmentIds: [UUID] {
        attachments.map(\.id)
    }

    func makeEventPayload() -> InboxEnqueuedPayload {
        InboxEnqueuedPayload(
            title: title,
            detail: detail,
            source: source,
            suggestions: suggestions,
            attachments: attachments
        )
    }
}

enum SharedInboxSource: String, Codable {
    case share
    case camera
    case csv
}

struct SharedInboxSuggestion: Codable, Hashable {
    let classification: String
    let confidence: Double?

    init(classification: String, confidence: Double? = nil) {
        self.classification = classification
        self.confidence = confidence
    }
}

struct SharedInboxAttachment: Codable, Identifiable {
    let id: UUID
    let filename: String
    let relativePath: String
    let uniformTypeIdentifier: String

    init(id: UUID = UUID(), filename: String, relativePath: String, uniformTypeIdentifier: String) {
        self.id = id
        self.filename = filename
        self.relativePath = relativePath
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }
}

struct InboxEnqueuedPayload: Encodable {
    let title: String?
    let detail: String?
    let source: SharedInboxSource
    let suggestions: [SharedInboxSuggestion]
    let attachments: [SharedInboxAttachment]
}

enum SharedInboxQueueError: Error {
    case missingAppGroupContainer
    case unavailableUserDefaults
    case encodingFailed(Error)
    case decodingFailed(Error)
}
