import Foundation

private func unionOrdered<T: Hashable>(_ lhs: [T], _ rhs: [T]) -> [T] {
    var seen: Set<T> = []
    var result: [T] = []
    for value in lhs + rhs {
        if seen.insert(value).inserted {
            result.append(value)
        }
    }
    return result
}

struct AppUserSnapshot: Codable {
    var identifier: UUID
    var createdAt: Date

    init(model: AppUser) {
        self.identifier = model.identifier
        self.createdAt = model.createdAt
    }

    func makeModel() -> AppUser {
        AppUser(identifier: identifier, createdAt: createdAt)
    }

    func apply(to model: AppUser) {
        model.createdAt = createdAt
    }
}

struct AccountSnapshot: Codable {
    var id: UUID
    var name: String
    var type: String
    var institution: String?
    var lastSync: Date?

    init(model: Account) {
        self.id = model.id
        self.name = model.name
        self.type = model.type
        self.institution = model.institution
        self.lastSync = model.lastSync
    }

    func makeModel() throws -> Account {
        try Account(id: id, name: name, type: type, institution: institution, lastSync: lastSync)
    }

    func apply(to model: Account) {
        model.name = name
        model.type = type
        model.institution = institution
        model.lastSync = lastSync
    }
}

struct MerchantSnapshot: Codable {
    var id: UUID
    var name: String
    var category: String?
    var address: String?

    init(model: Merchant) {
        self.id = model.id
        self.name = model.name
        self.category = model.category
        self.address = model.address
    }

    func makeModel() throws -> Merchant {
        try Merchant(id: id, name: name, category: category, address: address)
    }

    func apply(to model: Merchant) {
        model.name = name
        model.category = category
        model.address = address
    }
}

struct TransactionSnapshot: Codable {
    var id: UUID
    var accountId: UUID?
    var amount: Decimal
    var currency: String
    var date: Date
    var merchantId: UUID?
    var tags: [String]
    var source: String
    var attachmentIds: [UUID]

    init(model: Transaction) {
        self.id = model.id
        self.accountId = model.accountId
        self.amount = model.amount
        self.currency = model.currency
        self.date = model.date
        self.merchantId = model.merchantId
        self.tags = model.tags
        self.source = model.source
        self.attachmentIds = model.attachmentIds
    }

    func makeModel() throws -> Transaction {
        try Transaction(
            id: id,
            accountId: accountId,
            amount: amount,
            currency: currency,
            date: date,
            merchantId: merchantId,
            tags: tags,
            source: source,
            attachmentIds: attachmentIds
        )
    }

    func apply(to model: Transaction) {
        model.accountId = accountId
        model.amount = amount
        model.currency = currency
        model.date = date
        model.merchantId = merchantId
        model.tags = unionOrdered(model.tags, tags)
        model.source = source
        model.attachmentIds = unionOrdered(model.attachmentIds, attachmentIds)
    }
}

struct InventoryItemSnapshot: Codable {
    var id: UUID
    var name: String
    var barcode: String?
    var qty: Double
    var unit: String
    var locationId: UUID?
    var expiry: Date?
    var restockThreshold: Decimal
    var tags: [String]
    var lastPricePaid: Decimal?

    init(model: InventoryItem) {
        self.id = model.id
        self.name = model.name
        self.barcode = model.barcode
        self.qty = model.qty
        self.unit = model.unit
        self.locationId = model.locationId
        self.expiry = model.expiry
        self.restockThreshold = model.restockThreshold
        self.tags = model.tags
        self.lastPricePaid = model.lastPricePaid
    }

    func makeModel() throws -> InventoryItem {
        try InventoryItem(
            id: id,
            name: name,
            barcode: barcode,
            qty: qty,
            unit: unit,
            locationId: locationId,
            expiry: expiry,
            restockThreshold: restockThreshold,
            tags: tags,
            lastPricePaid: lastPricePaid
        )
    }

    func apply(to model: InventoryItem) {
        model.name = name
        model.barcode = barcode
        model.qty = qty
        model.unit = unit
        model.locationId = locationId
        model.expiry = expiry
        model.restockThreshold = restockThreshold
        model.tags = unionOrdered(model.tags, tags)
        model.lastPricePaid = lastPricePaid
    }
}

struct LocationBinSnapshot: Codable {
    var id: UUID
    var name: String
    var kind: String

    init(model: LocationBin) {
        self.id = model.id
        self.name = model.name
        self.kind = model.kind
    }

    func makeModel() throws -> LocationBin {
        try LocationBin(id: id, name: name, kind: kind)
    }

    func apply(to model: LocationBin) {
        model.name = name
        model.kind = kind
    }
}

struct ShoppingListSnapshot: Codable {
    var id: UUID
    var name: String

    init(model: ShoppingList) {
        self.id = model.id
        self.name = model.name
    }

    func makeModel() throws -> ShoppingList {
        try ShoppingList(id: id, name: name)
    }

    func apply(to model: ShoppingList) {
        model.name = name
    }
}

struct ShoppingListLineSnapshot: Codable {
    var id: UUID
    var inventoryItemId: UUID?
    var name: String
    var desiredQty: Double
    var status: String
    var preferredMerchantId: UUID?
    var listId: UUID?

    init(model: ShoppingListLine) {
        self.id = model.id
        self.inventoryItemId = model.inventoryItemId
        self.name = model.name
        self.desiredQty = model.desiredQty
        self.status = model.status
        self.preferredMerchantId = model.preferredMerchantId
        self.listId = model.list?.id
    }

    func makeModel(list: ShoppingList?) throws -> ShoppingListLine {
        try ShoppingListLine(
            id: id,
            inventoryItemId: inventoryItemId,
            name: name,
            desiredQty: desiredQty,
            status: status,
            preferredMerchantId: preferredMerchantId,
            list: list
        )
    }

    func apply(to model: ShoppingListLine, list: ShoppingList?) {
        model.inventoryItemId = inventoryItemId
        model.name = name
        model.desiredQty = desiredQty
        model.status = status
        model.preferredMerchantId = preferredMerchantId
        model.list = list
    }
}

struct HabitSnapshot: Codable {
    var id: UUID
    var name: String
    var scheduleRule: String
    var unit: String
    var target: Double
    var streak: Int
    var lastCheckIn: Date?

    init(model: Habit) {
        self.id = model.id
        self.name = model.name
        self.scheduleRule = model.scheduleRule
        self.unit = model.unit
        self.target = model.target
        self.streak = model.streak
        self.lastCheckIn = model.lastCheckIn
    }

    func makeModel() throws -> Habit {
        try Habit(
            id: id,
            name: name,
            scheduleRule: scheduleRule,
            unit: unit,
            target: target,
            streak: streak,
            lastCheckIn: lastCheckIn
        )
    }

    func apply(to model: Habit) {
        model.name = name
        model.scheduleRule = scheduleRule
        model.unit = unit
        model.target = target
        model.streak = streak
        model.lastCheckIn = lastCheckIn
    }
}

struct TaskLinkSnapshot: Codable {
    var id: UUID
    var reminderIdentifier: String
    var relatedEntityRef: String

    init(model: TaskLink) {
        self.id = model.id
        self.reminderIdentifier = model.reminderIdentifier
        self.relatedEntityRef = model.relatedEntityRef
    }

    func makeModel() throws -> TaskLink {
        try TaskLink(id: id, reminderIdentifier: reminderIdentifier, relatedEntityRef: relatedEntityRef)
    }

    func apply(to model: TaskLink) {
        model.reminderIdentifier = reminderIdentifier
        model.relatedEntityRef = relatedEntityRef
    }
}

struct CalendarLinkSnapshot: Codable {
    var id: UUID
    var eventIdentifier: String
    var relatedEntityRef: String

    init(model: CalendarLink) {
        self.id = model.id
        self.eventIdentifier = model.eventIdentifier
        self.relatedEntityRef = model.relatedEntityRef
    }

    func makeModel() throws -> CalendarLink {
        try CalendarLink(id: id, eventIdentifier: eventIdentifier, relatedEntityRef: relatedEntityRef)
    }

    func apply(to model: CalendarLink) {
        model.eventIdentifier = eventIdentifier
        model.relatedEntityRef = relatedEntityRef
    }
}

struct AttachmentSnapshot: Codable {
    var id: UUID
    var kind: String
    var localURL: String
    var ocrText: String?

    init(model: Attachment) {
        self.id = model.id
        self.kind = model.kind
        self.localURL = model.localURL.absoluteString
        self.ocrText = model.ocrText
    }

    func makeModel() throws -> Attachment {
        guard let url = URL(string: localURL) else {
            throw URLError(.badURL)
        }
        return try Attachment(id: id, kind: kind, localURL: url, ocrText: ocrText)
    }

    func apply(to model: Attachment) {
        model.kind = kind
        if let url = URL(string: localURL) {
            model.localURL = url
        }
        model.ocrText = ocrText
    }
}

struct BudgetEnvelopeSnapshot: Codable {
    var id: UUID
    var name: String
    var monthlyLimit: Decimal
    var currency: String
    var tags: [String]
    var notes: String?
    var createdAt: Date

    init(model: BudgetEnvelope) {
        self.id = model.id
        self.name = model.name
        self.monthlyLimit = model.monthlyLimit
        self.currency = model.currency
        self.tags = model.tags
        self.notes = model.notes
        self.createdAt = model.createdAt
    }

    func makeModel() throws -> BudgetEnvelope {
        try BudgetEnvelope(
            id: id,
            name: name,
            monthlyLimit: monthlyLimit,
            currency: currency,
            tags: tags,
            notes: notes,
            createdAt: createdAt
        )
    }

    func apply(to model: BudgetEnvelope) {
        model.name = name
        model.monthlyLimit = monthlyLimit
        model.currency = currency
        model.tags = unionOrdered(model.tags, tags)
        model.notes = notes
        model.createdAt = createdAt
    }
}

struct PersonLinkSnapshot: Codable {
    var id: UUID
    var contactIdentifier: String
    var role: String

    init(model: PersonLink) {
        self.id = model.id
        self.contactIdentifier = model.contactIdentifier
        self.role = model.role
    }

    func makeModel() throws -> PersonLink {
        try PersonLink(id: id, contactIdentifier: contactIdentifier, role: role)
    }

    func apply(to model: PersonLink) {
        model.contactIdentifier = contactIdentifier
        model.role = role
    }
}

struct RuleSpecSnapshot: Codable {
    var id: UUID
    var name: String
    var trigger: String
    var conditions: [String]
    var actions: [String]
    var enabled: Bool

    init(model: RuleSpec) {
        self.id = model.id
        self.name = model.name
        self.trigger = model.trigger
        self.conditions = model.conditions
        self.actions = model.actions
        self.enabled = model.enabled
    }

    func makeModel() throws -> RuleSpec {
        try RuleSpec(
            id: id,
            name: name,
            trigger: trigger,
            conditions: conditions,
            actions: actions,
            enabled: enabled
        )
    }

    func apply(to model: RuleSpec) {
        model.name = name
        model.trigger = trigger
        model.conditions = unionOrdered(model.conditions, conditions)
        model.actions = unionOrdered(model.actions, actions)
        model.enabled = enabled
    }
}

struct EventRecordSnapshot: Codable {
    var id: UUID
    var kind: String
    var payloadJSON: String
    var occurredAt: Date
    var relatedIds: [UUID]

    init(model: EventRecord) {
        self.id = model.id
        self.kind = model.kind
        self.payloadJSON = model.payloadJSON
        self.occurredAt = model.occurredAt
        self.relatedIds = model.relatedIds
    }

    func makeModel() throws -> EventRecord {
        try EventRecord(id: id, kind: kind, payloadJSON: payloadJSON, occurredAt: occurredAt, relatedIds: relatedIds)
    }

    func apply(to model: EventRecord) {
        model.kind = kind
        model.payloadJSON = payloadJSON
        model.occurredAt = occurredAt
        model.relatedIds = unionOrdered(model.relatedIds, relatedIds)
    }
}
