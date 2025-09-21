import Foundation

@MainActor
struct ShareInboxImporter {
    private let persistence: PersistenceController
    private let events: EventDispatcher

    init(persistence: PersistenceController, events: EventDispatcher) {
        self.persistence = persistence
        self.events = events
    }

    func importPendingItems() {
        let queue = SharedInboxQueue()
        let pendingItems = queue.dequeueAll()
        guard !pendingItems.isEmpty else { return }

        for item in pendingItems {
            do {
                let payload = item.makeEventPayload()
                let json = try encodePayload(payload)
                try persistence.eventStore.append(
                    kind: DomainEventKind.inboxEnqueued.rawValue,
                    payloadJSON: json,
                    occurredAt: item.receivedAt,
                    relatedIds: item.relatedAttachmentIds
                )

                events.post(
                    kind: .inboxEnqueued,
                    payload: [
                        "inboxItemId": item.id.uuidString,
                        "title": item.title ?? "Incoming item"
                    ],
                    occurredAt: item.receivedAt
                )
            } catch {
                assertionFailure("Failed to import shared inbox item: \(error)")
            }
        }
    }

    private func encodePayload(_ payload: InboxEnqueuedPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
