import Combine
import Foundation

enum DomainEventKind: String {
    case receiptScanned = "receipt.scanned"
    case barcodeScanned = "barcode.scanned"
    case inventoryAdded = "inventory.added"
    case inventoryAdjusted = "inventory.adjusted"
    case inventoryLow = "inventory.low"
    case shoppingChecked = "shopping.checked"
    case shoppingCreated = "shopping.created"
    case transactionLogged = "transaction.logged"
    case accountCsvImported = "account.csvImported"
    case habitStarted = "habit.started"
    case habitTicked = "habit.ticked"
    case habitCompleted = "habit.completed"
    case habitSkipped = "habit.skipped"
    case calendarEventLinked = "calendar.eventLinked"
    case reminderCreated = "reminder.created"
    case geoEntered = "geo.entered"
    case geoExited = "geo.exited"
    case ruleFired = "rule.fired"
    case ruleFailed = "rule.failed"
    case inboxEnqueued = "inbox.enqueued"
    case inboxClassified = "inbox.classified"
    case inboxDismissed = "inbox.dismissed"
}

struct DomainEvent {
    let kind: DomainEventKind
    let payload: [String: Any]
    let occurredAt: Date

    init(kind: DomainEventKind, payload: [String: Any] = [:], occurredAt: Date = .now) {
        self.kind = kind
        self.payload = payload
        self.occurredAt = occurredAt
    }
}

final class EventDispatcher {
    private let subject = PassthroughSubject<DomainEvent, Never>()

    @discardableResult
    func subscribe(_ receive: @escaping (DomainEvent) -> Void) -> AnyCancellable {
        subject.sink(receiveValue: receive)
    }

    func post(_ event: DomainEvent) {
        subject.send(event)
    }

    func post(kind: DomainEventKind, payload: [String: Any] = [:], occurredAt: Date = .now) {
        post(DomainEvent(kind: kind, payload: payload, occurredAt: occurredAt))
    }
}
