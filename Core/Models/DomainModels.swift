import Foundation
import SwiftData

// MARK: - Attribute Transformers

struct DecimalAttributeTransformer: AttributeTransformer {
    typealias Value = Decimal
    typealias RawValue = NSDecimalNumber

    static func toRaw(_ value: Decimal) -> NSDecimalNumber {
        NSDecimalNumber(decimal: value)
    }

    static func fromRaw(_ rawValue: NSDecimalNumber) -> Decimal {
        rawValue.decimalValue
    }
}

struct SecureBookmarkTransformer: AttributeTransformer {
    typealias Value = URL
    typealias RawValue = Data

    static func toRaw(_ value: URL) -> Data {
        do {
            return try value.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            fatalError("Failed to create security-scoped bookmark for URL: \(error)")
        }
    }

    static func fromRaw(_ rawValue: Data) -> URL {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: rawValue, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard !isStale else {
                fatalError("Security-scoped bookmark is stale and requires regeneration.")
            }
            return url
        } catch {
            fatalError("Failed to resolve security-scoped bookmark: \(error)")
        }
    }
}

struct CodableTransformer<Value: Codable>: AttributeTransformer {
    typealias RawValue = Data

    static func toRaw(_ value: Value) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            fatalError("Failed to encode transformable value: \(error)")
        }
    }

    static func fromRaw(_ rawValue: Data) -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: rawValue)
        } catch {
            fatalError("Failed to decode transformable value: \(error)")
        }
    }
}

// MARK: - Validation

enum ModelValidationError: LocalizedError {
    case emptyValue(field: String)
    case negativeValue(field: String)
    case nonPositiveValue(field: String)
    case invalidCurrency
    case zeroValueNotAllowed(field: String)

    var errorDescription: String? {
        switch self {
        case let .emptyValue(field):
            return "The \(field) must not be empty."
        case let .negativeValue(field):
            return "The \(field) must not be negative."
        case let .nonPositiveValue(field):
            return "The \(field) must be greater than zero."
        case .invalidCurrency:
            return "The currency must be a three-letter ISO 4217 code."
        case let .zeroValueNotAllowed(field):
            return "The \(field) must not be zero."
        }
    }
}

private func sanitizedNonEmpty(_ value: String, fieldName: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ModelValidationError.emptyValue(field: fieldName) }
    return trimmed
}

private func validatedNonNegative<T: Comparable & Numeric>(_ value: T, fieldName: String) throws -> T {
    if value < .zero {
        throw ModelValidationError.negativeValue(field: fieldName)
    }
    return value
}

private func validatedPositive<T: Comparable & Numeric>(_ value: T, fieldName: String) throws -> T {
    if value <= .zero {
        throw ModelValidationError.nonPositiveValue(field: fieldName)
    }
    return value
}

private func validatedNonZero(_ value: Decimal, fieldName: String) throws -> Decimal {
    if value == .zero {
        throw ModelValidationError.zeroValueNotAllowed(field: fieldName)
    }
    return value
}

// MARK: - Models

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: String
    var institution: String?
    var lastSync: Date?

    init(id: UUID = UUID(), name: String, type: String, institution: String? = nil, lastSync: Date? = nil) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Account name")
        self.type = try sanitizedNonEmpty(type, fieldName: "Account type")
        if let institution {
            self.institution = try sanitizedNonEmpty(institution, fieldName: "Institution")
        } else {
            self.institution = nil
        }
        self.lastSync = lastSync
    }
}

@Model
final class Merchant {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: String?
    var address: String?

    init(id: UUID = UUID(), name: String, category: String? = nil, address: String? = nil) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Merchant name")
        if let category {
            self.category = try sanitizedNonEmpty(category, fieldName: "Category")
        } else {
            self.category = nil
        }
        if let address {
            self.address = try sanitizedNonEmpty(address, fieldName: "Address")
        } else {
            self.address = nil
        }
    }
}

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var accountId: UUID?
    @Attribute(.transformable(by: DecimalAttributeTransformer.self)) var amount: Decimal
    var currency: String
    var date: Date
    var merchantId: UUID?
    @Attribute(.transformable(by: CodableTransformer<[String]>.self)) var tags: [String]
    var source: String
    @Attribute(.transformable(by: CodableTransformer<[UUID]>.self)) var attachmentIds: [UUID]

    init(
        id: UUID = UUID(),
        accountId: UUID? = nil,
        amount: Decimal,
        currency: String,
        date: Date,
        merchantId: UUID? = nil,
        tags: [String] = [],
        source: String,
        attachmentIds: [UUID] = []
    ) throws {
        self.id = id
        self.accountId = accountId
        self.amount = try validatedNonZero(amount, fieldName: "Amount")
        let sanitizedCurrency = try sanitizedNonEmpty(currency, fieldName: "Currency").uppercased()
        guard sanitizedCurrency.count == 3 else { throw ModelValidationError.invalidCurrency }
        self.currency = sanitizedCurrency
        self.date = date
        self.merchantId = merchantId
        self.tags = tags
        self.source = try sanitizedNonEmpty(source, fieldName: "Source")
        self.attachmentIds = attachmentIds
    }
}

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var barcode: String?
    var qty: Double
    var unit: String
    var locationId: UUID?
    var expiry: Date?
    @Attribute(.transformable(by: DecimalAttributeTransformer.self)) var restockThreshold: Decimal
    @Attribute(.transformable(by: CodableTransformer<[String]>.self)) var tags: [String]
    @Attribute(.transformable(by: DecimalAttributeTransformer.self)) var lastPricePaid: Decimal?

    init(
        id: UUID = UUID(),
        name: String,
        barcode: String? = nil,
        qty: Double,
        unit: String,
        locationId: UUID? = nil,
        expiry: Date? = nil,
        restockThreshold: Decimal,
        tags: [String] = [],
        lastPricePaid: Decimal? = nil
    ) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Item name")
        if let barcode {
            self.barcode = try sanitizedNonEmpty(barcode, fieldName: "Barcode")
        } else {
            self.barcode = nil
        }
        self.qty = try validatedNonNegative(qty, fieldName: "Quantity")
        self.unit = try sanitizedNonEmpty(unit, fieldName: "Unit")
        self.locationId = locationId
        self.expiry = expiry
        self.restockThreshold = try validatedNonNegative(restockThreshold, fieldName: "Restock threshold")
        self.tags = tags
        if let lastPricePaid {
            self.lastPricePaid = try validatedPositive(lastPricePaid, fieldName: "Last price paid")
        } else {
            self.lastPricePaid = nil
        }
    }
}

@Model
final class LocationBin {
    @Attribute(.unique) var id: UUID
    var name: String
    var kind: String

    init(id: UUID = UUID(), name: String, kind: String) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Location name")
        self.kind = try sanitizedNonEmpty(kind, fieldName: "Location kind")
    }
}

@Model
final class ShoppingList {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \ShoppingListLine.list) var lines: [ShoppingListLine]

    init(id: UUID = UUID(), name: String, lines: [ShoppingListLine] = []) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Shopping list name")
        self.lines = lines
        lines.forEach { $0.list = self }
    }
}

@Model
final class ShoppingListLine {
    @Attribute(.unique) var id: UUID
    var inventoryItemId: UUID?
    var name: String
    var desiredQty: Double
    var status: String
    var preferredMerchantId: UUID?
    @Relationship var list: ShoppingList?

    init(
        id: UUID = UUID(),
        inventoryItemId: UUID? = nil,
        name: String,
        desiredQty: Double,
        status: String,
        preferredMerchantId: UUID? = nil,
        list: ShoppingList? = nil
    ) throws {
        self.id = id
        self.inventoryItemId = inventoryItemId
        self.name = try sanitizedNonEmpty(name, fieldName: "Line name")
        self.desiredQty = try validatedNonNegative(desiredQty, fieldName: "Desired quantity")
        self.status = try sanitizedNonEmpty(status, fieldName: "Status")
        self.preferredMerchantId = preferredMerchantId
        self.list = list
    }
}

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var scheduleRule: String
    var unit: String
    var target: Double
    var streak: Int
    var lastCheckIn: Date?

    init(
        id: UUID = UUID(),
        name: String,
        scheduleRule: String,
        unit: String,
        target: Double,
        streak: Int = 0,
        lastCheckIn: Date? = nil
    ) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Habit name")
        self.scheduleRule = try sanitizedNonEmpty(scheduleRule, fieldName: "Schedule rule")
        self.unit = try sanitizedNonEmpty(unit, fieldName: "Unit")
        self.target = try validatedPositive(target, fieldName: "Target")
        guard streak >= 0 else { throw ModelValidationError.negativeValue(field: "Streak") }
        self.streak = streak
        self.lastCheckIn = lastCheckIn
    }
}

@Model
final class TaskLink {
    @Attribute(.unique) var id: UUID
    var reminderIdentifier: String
    var relatedEntityRef: String

    init(id: UUID = UUID(), reminderIdentifier: String, relatedEntityRef: String) throws {
        self.id = id
        self.reminderIdentifier = try sanitizedNonEmpty(reminderIdentifier, fieldName: "Reminder identifier")
        self.relatedEntityRef = try sanitizedNonEmpty(relatedEntityRef, fieldName: "Related entity reference")
    }
}

@Model
final class CalendarLink {
    @Attribute(.unique) var id: UUID
    var eventIdentifier: String
    var relatedEntityRef: String

    init(id: UUID = UUID(), eventIdentifier: String, relatedEntityRef: String) throws {
        self.id = id
        self.eventIdentifier = try sanitizedNonEmpty(eventIdentifier, fieldName: "Event identifier")
        self.relatedEntityRef = try sanitizedNonEmpty(relatedEntityRef, fieldName: "Related entity reference")
    }
}

@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var kind: String
    @Attribute(.transformable(by: SecureBookmarkTransformer.self)) var localURL: URL
    var ocrText: String?

    init(id: UUID = UUID(), kind: String, localURL: URL, ocrText: String? = nil) throws {
        self.id = id
        self.kind = try sanitizedNonEmpty(kind, fieldName: "Attachment kind")
        self.localURL = localURL
        if let ocrText {
            self.ocrText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.ocrText = nil
        }
    }
}

@Model
final class BudgetEnvelope {
    @Attribute(.unique) var id: UUID
    var name: String
    @Attribute(.transformable(by: DecimalAttributeTransformer.self)) var monthlyLimit: Decimal
    var currency: String
    @Attribute(.transformable(by: CodableTransformer<[String]>.self)) var tags: [String]
    var notes: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        monthlyLimit: Decimal,
        currency: String,
        tags: [String] = [],
        notes: String? = nil,
        createdAt: Date = .now
    ) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Envelope name")
        self.monthlyLimit = try validatedPositive(monthlyLimit, fieldName: "Monthly limit")
        let sanitizedCurrency = try sanitizedNonEmpty(currency, fieldName: "Currency").uppercased()
        guard sanitizedCurrency.count == 3 else { throw ModelValidationError.invalidCurrency }
        self.currency = sanitizedCurrency
        self.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let notes {
            self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.notes = nil
        }
        self.createdAt = createdAt
    }
}

@Model
final class PersonLink {
    @Attribute(.unique) var id: UUID
    var contactIdentifier: String
    var role: String

    init(id: UUID = UUID(), contactIdentifier: String, role: String) throws {
        self.id = id
        self.contactIdentifier = try sanitizedNonEmpty(contactIdentifier, fieldName: "Contact identifier")
        self.role = try sanitizedNonEmpty(role, fieldName: "Role")
    }
}

@Model
final class RuleSpec {
    @Attribute(.unique) var id: UUID
    var name: String
    var trigger: String
    @Attribute(.transformable(by: CodableTransformer<[String]>.self)) var conditions: [String]
    @Attribute(.transformable(by: CodableTransformer<[String]>.self)) var actions: [String]
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        trigger: String,
        conditions: [String] = [],
        actions: [String] = [],
        enabled: Bool = true
    ) throws {
        self.id = id
        self.name = try sanitizedNonEmpty(name, fieldName: "Rule name")
        self.trigger = try sanitizedNonEmpty(trigger, fieldName: "Trigger")
        self.conditions = conditions
        self.actions = actions
        self.enabled = enabled
    }
}

@Model
final class EventRecord {
    @Attribute(.unique) var id: UUID
    var kind: String
    var payloadJSON: String
    var occurredAt: Date
    @Attribute(.transformable(by: CodableTransformer<[UUID]>.self)) var relatedIds: [UUID]

    init(id: UUID = UUID(), kind: String, payloadJSON: String, occurredAt: Date = .now, relatedIds: [UUID] = []) throws {
        self.id = id
        self.kind = try sanitizedNonEmpty(kind, fieldName: "Event kind")
        self.payloadJSON = try sanitizedNonEmpty(payloadJSON, fieldName: "Payload JSON")
        self.occurredAt = occurredAt
        self.relatedIds = relatedIds
    }
}
