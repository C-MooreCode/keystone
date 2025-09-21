import AppIntents
import Foundation
import SwiftData

struct LowStockResult {
    let items: [ItemSummary]
    let payload: [String: Any]
}

@MainActor
struct IntentUseCases {
    let services: ServiceContainer

    init(services: ServiceContainer = IntentDependencyContainer.shared.services) {
        self.services = services
    }

    func logExpense(amount: Decimal, merchant: String?, note: String?, attachment: URL?) async throws -> [String: Any] {
        let payload = sanitizedPayload([
            "amount": amount.asDouble,
            "merchant": merchant?.trimmedOrNil,
            "note": note?.trimmedOrNil,
            "attachment": attachment?.absoluteString
        ])
        try recordEvent(kind: .transactionLogged, payload: payload)
        return payload
    }

    func addInventory(
        name: String?,
        barcode: String?,
        quantity: Double,
        unit: String,
        location: String?,
        tags: [String]?
    ) async throws -> [String: Any] {
        let repository = services.persistence.inventoryItems
        let locationBin = try resolveLocation(named: location)
        let locationId = locationBin?.id

        if let barcode, let existing = try repository.first(where: #Predicate { $0.barcode == barcode }) {
            try repository.performAndSave {
                existing.qty += quantity
                existing.unit = unit
                existing.locationId = locationId
                if let tags, !tags.isEmpty {
                    existing.tags = tags
                }
            }
            let payload = sanitizedPayload([
                "itemId": existing.id.uuidString,
                "name": existing.name,
                "barcode": barcode,
                "quantity": existing.qty,
                "unit": existing.unit,
                "locationId": locationId?.uuidString,
                "tags": existing.tags
            ])
            try recordEvent(kind: .inventoryAdded, payload: payload)
            return payload
        }

        if let name, let existing = try repository.first(where: #Predicate { $0.name == name }) {
            try repository.performAndSave {
                existing.qty += quantity
                existing.unit = unit
                existing.locationId = locationId
                if let barcode {
                    existing.barcode = barcode
                }
                if let tags, !tags.isEmpty {
                    existing.tags = tags
                }
            }
            let payload = sanitizedPayload([
                "itemId": existing.id.uuidString,
                "name": existing.name,
                "barcode": existing.barcode,
                "quantity": existing.qty,
                "unit": existing.unit,
                "locationId": locationId?.uuidString,
                "tags": existing.tags
            ])
            try recordEvent(kind: .inventoryAdded, payload: payload)
            return payload
        }

        guard let itemName = name?.trimmedOrNil ?? barcode?.trimmedOrNil else {
            throw IntentExecutionError.missingInventoryName
        }

        let newItem = try repository.create {
            try InventoryItem(
                name: itemName,
                barcode: barcode?.trimmedOrNil,
                qty: quantity,
                unit: unit,
                locationId: locationId,
                restockThreshold: .zero,
                tags: tags ?? []
            )
        }

        let payload = sanitizedPayload([
            "itemId": newItem.id.uuidString,
            "name": newItem.name,
            "barcode": newItem.barcode,
            "quantity": newItem.qty,
            "unit": newItem.unit,
            "locationId": locationId?.uuidString,
            "tags": newItem.tags
        ])
        try recordEvent(kind: .inventoryAdded, payload: payload)
        return payload
    }

    func adjustInventory(itemReference: String, deltaQuantity: Double) async throws -> [String: Any] {
        let item = try findInventoryItem(reference: itemReference)
        let repository = services.persistence.inventoryItems
        try repository.performAndSave {
            let updated = item.qty + deltaQuantity
            item.qty = max(0, updated)
        }

        let payload = sanitizedPayload([
            "itemId": item.id.uuidString,
            "name": item.name,
            "delta": deltaQuantity,
            "quantity": item.qty
        ])
        try recordEvent(kind: .inventoryAdjusted, payload: payload)
        return payload
    }

    func addToShoppingList(
        itemIdentifier: String,
        quantity: Double,
        listName: String?
    ) async throws -> [String: Any] {
        let list = try resolveShoppingList(named: listName)
        let existingItem = try? findInventoryItem(reference: itemIdentifier)
        let lineName = existingItem?.name ?? itemIdentifier

        let line = try services.persistence.shoppingListLines.create {
            try ShoppingListLine(
                inventoryItemId: existingItem?.id,
                name: lineName,
                desiredQty: quantity,
                status: "pending",
                list: list
            )
        }

        let payload = sanitizedPayload([
            "listId": list.id.uuidString,
            "listName": list.name,
            "lineId": line.id.uuidString,
            "itemId": existingItem?.id.uuidString,
            "itemName": lineName,
            "quantity": quantity
        ])
        try recordEvent(kind: .shoppingCreated, payload: payload)
        return payload
    }

    func markBought(reference: String) async throws -> [String: Any] {
        if let uuid = UUID(uuidString: reference),
           let line = try services.persistence.shoppingListLines.first(where: #Predicate { $0.id == uuid }) {
            try services.persistence.shoppingListLines.performAndSave {
                line.status = "purchased"
            }
            let payload = sanitizedPayload([
                "lineId": line.id.uuidString,
                "listId": line.list?.id.uuidString,
                "itemName": line.name
            ])
            try recordEvent(kind: .shoppingChecked, payload: payload)
            return payload
        }

        let list = try resolveShoppingList(named: reference)
        try services.persistence.shoppingListLines.performAndSave {
            list.lines.forEach { $0.status = "purchased" }
        }

        let payload = sanitizedPayload([
            "listId": list.id.uuidString,
            "listName": list.name,
            "count": list.lines.count
        ])
        try recordEvent(kind: .shoppingChecked, payload: payload)
        return payload
    }

    func startHabit(habitReference: String, target: Double?) async throws -> [String: Any] {
        let habit = try findHabit(reference: habitReference)
        try services.persistence.habits.performAndSave {
            if let target {
                habit.target = target
            }
            habit.lastCheckIn = .now
            if habit.streak < 0 {
                habit.streak = 0
            }
        }

        let payload = sanitizedPayload([
            "habitId": habit.id.uuidString,
            "habitName": habit.name,
            "target": habit.target
        ])
        try recordEvent(kind: .habitStarted, payload: payload)
        return payload
    }

    func tickHabit(habitReference: String, amount: Double?) async throws -> [String: Any] {
        let habit = try findHabit(reference: habitReference)
        let increment = amount ?? 1
        var completed = false

        try services.persistence.habits.performAndSave {
            habit.lastCheckIn = .now
            if increment >= habit.target {
                habit.streak += 1
                completed = true
            }
        }

        let payload = sanitizedPayload([
            "habitId": habit.id.uuidString,
            "habitName": habit.name,
            "amount": increment,
            "streak": habit.streak,
            "completed": completed
        ])
        try recordEvent(kind: .habitTicked, payload: payload)

        if completed {
            let completionPayload = sanitizedPayload([
                "habitId": habit.id.uuidString,
                "habitName": habit.name,
                "streak": habit.streak
            ])
            try recordEvent(kind: .habitCompleted, payload: completionPayload)
        }

        return payload
    }

    func whatIsLow(filter: String?) async throws -> LowStockResult {
        let items = try services.persistence.inventoryItems.fetch()
        let summaries = items.compactMap { item -> ItemSummary? in
            let threshold = item.restockThreshold.asDouble
            guard threshold > 0, item.qty <= threshold else { return nil }
            return ItemSummary(
                id: item.id,
                name: item.name,
                quantity: item.qty,
                threshold: threshold
            )
        }

        let filtered: [ItemSummary]
        if let filter, let lowered = filter.trimmedOrNil?.lowercased(), !lowered.isEmpty {
            filtered = summaries.filter { summary in
                summary.name.lowercased().contains(lowered)
            }
        } else {
            filtered = summaries
        }

        let payload = sanitizedPayload([
            "filter": filter?.trimmedOrNil,
            "count": filtered.count
        ])
        try recordEvent(kind: .inventoryLow, payload: payload)
        return LowStockResult(items: filtered, payload: payload)
    }

    func importCSV(fileURL: URL, type: String) async throws -> [String: Any] {
        switch type.lowercased() {
        case "inventory":
            let records = try await services.csvImporter.importInventory(from: fileURL)
            let payload = sanitizedPayload([
                "type": "inventory",
                "count": records.count,
                "file": fileURL.absoluteString
            ])
            try recordEvent(kind: .accountCsvImported, payload: payload)
            return payload
        case "transactions":
            let formatters = DateFormatter.transactionFormatters
            let records = try await services.csvImporter.importTransactions(
                from: fileURL,
                dateFormatters: formatters
            )
            let payload = sanitizedPayload([
                "type": "transactions",
                "count": records.count,
                "file": fileURL.absoluteString
            ])
            try recordEvent(kind: .accountCsvImported, payload: payload)
            return payload
        default:
            throw IntentExecutionError.unsupportedCSVType(type)
        }
    }

    func runRule(named ruleName: String) async throws -> [String: Any] {
        guard let rule = try services.persistence.ruleSpecs.first(where: #Predicate { $0.name == ruleName }) else {
            throw IntentExecutionError.ruleNotFound(ruleName)
        }

        let payload = sanitizedPayload([
            "ruleId": rule.id.uuidString,
            "ruleName": rule.name
        ])
        try recordEvent(kind: .ruleFired, payload: payload)
        return payload
    }
}

private extension IntentUseCases {
    func recordEvent(kind: DomainEventKind, payload: [String: Any]) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        _ = try services.persistence.eventStore.append(
            kind: kind.rawValue,
            payloadJSON: jsonString,
            occurredAt: .now
        )
    }

    func resolveLocation(named name: String?) throws -> LocationBin? {
        guard let raw = name?.trimmedOrNil, !raw.isEmpty else {
            return nil
        }

        if let existing = try services.persistence.locationBins.first(where: #Predicate { $0.name == raw }) {
            return existing
        }

        return try services.persistence.locationBins.create {
            try LocationBin(name: raw, kind: "shortcut")
        }
    }

    func resolveShoppingList(named name: String?) throws -> ShoppingList {
        let resolved = name?.trimmedOrNil ?? "Shopping"
        if let existing = try services.persistence.shoppingLists.first(where: #Predicate { $0.name == resolved }) {
            return existing
        }
        return try services.persistence.shoppingLists.create {
            try ShoppingList(name: resolved)
        }
    }

    func findInventoryItem(reference: String) throws -> InventoryItem {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: trimmed),
           let byId = try services.persistence.inventoryItems.first(where: #Predicate { $0.id == uuid }) {
            return byId
        }

        if let byBarcode = try services.persistence.inventoryItems.first(where: #Predicate { $0.barcode == trimmed }) {
            return byBarcode
        }

        if let byName = try services.persistence.inventoryItems.first(where: #Predicate { $0.name == trimmed }) {
            return byName
        }

        throw IntentExecutionError.inventoryItemNotFound(reference)
    }

    func findHabit(reference: String) throws -> Habit {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: trimmed),
           let byId = try services.persistence.habits.first(where: #Predicate { $0.id == uuid }) {
            return byId
        }

        if let byName = try services.persistence.habits.first(where: #Predicate { $0.name == trimmed }) {
            return byName
        }

        throw IntentExecutionError.habitNotFound(reference)
    }

    func sanitizedPayload(_ values: [String: Any?]) -> [String: Any] {
        var payload: [String: Any] = [:]
        for (key, value) in values {
            switch value {
            case let value as Double:
                payload[key] = value
            case let value as Int:
                payload[key] = value
            case let value as String:
                payload[key] = value
            case let value as Decimal:
                payload[key] = value.asDouble
            case let value as URL:
                payload[key] = value.absoluteString
            case let value as [String]:
                payload[key] = value
            case let value as UUID:
                payload[key] = value.uuidString
            case let value as Bool:
                payload[key] = value
            case let value?:
                payload[key] = value
            default:
                continue
            }
        }
        return payload
    }
}

private enum IntentExecutionError: LocalizedError {
    case missingInventoryName
    case inventoryItemNotFound(String)
    case habitNotFound(String)
    case unsupportedCSVType(String)
    case ruleNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingInventoryName:
            return "An item name or barcode is required."
        case let .inventoryItemNotFound(reference):
            return "Unable to locate an inventory item matching \(reference)."
        case let .habitNotFound(reference):
            return "Unable to locate a habit matching \(reference)."
        case let .unsupportedCSVType(type):
            return "Unsupported CSV import type: \(type)."
        case let .ruleNotFound(name):
            return "No rule named \(name) exists."
        }
    }
}

private extension Decimal {
    var asDouble: Double {
        (self as NSDecimalNumber).doubleValue
    }
}

private extension Optional where Wrapped == String {
    var trimmedOrNil: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension DateFormatter {
    static var transactionFormatters: [DateFormatter] {
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"

        let short = DateFormatter()
        short.dateFormat = "yyyy-MM-dd"

        let us = DateFormatter()
        us.dateFormat = "M/d/yyyy"

        return [iso, short, us]
    }
}
