import AppIntents
import Foundation

struct ItemSummary: Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let quantity: Double
    let threshold: Double
}

@MainActor
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense"
    static var description = IntentDescription("Record a quick expense entry in Keystone.")

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount)") {
            When(\.$merchant, .provided) {
                " at \(\.$merchant)"
            }
            When(\.$note, .provided) {
                " – \(\.$note)"
            }
        }
    }

    @Parameter(title: "Amount", description: "The expense amount to record.")
    var amount: Decimal

    @Parameter(title: "Merchant", description: "Optional merchant associated with the expense.", default: nil)
    var merchant: String?

    @Parameter(title: "Note", description: "Optional note for the expense.", default: nil)
    var note: String?

    @Parameter(title: "Attachment", description: "Optional file attachment URL for the expense.", default: nil)
    var attachment: URL?

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.logExpense(
            amount: amount,
            merchant: merchant,
            note: note,
            attachment: attachment
        )
        dependencies.services.events.post(kind: .transactionLogged, payload: payload)
        return .result()
    }
}

@MainActor
struct AddInventoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Inventory"
    static var description = IntentDescription("Add or update an inventory item with quantity information.")

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$quantity) \(\.$unit)") {
            When(\.$name, .provided) {
                " of \(\.$name)"
            }
            When(\.$barcode, .provided) {
                " (barcode \(\.$barcode))"
            }
        }
    }

    @Parameter(title: "Name", description: "The display name of the inventory item.", default: nil)
    var name: String?

    @Parameter(title: "Barcode", description: "An optional barcode for lookup and updates.", default: nil)
    var barcode: String?

    @Parameter(title: "Quantity", description: "Quantity to add or set for the item.")
    var quantity: Double

    @Parameter(title: "Unit", description: "Unit of measure for the quantity.")
    var unit: String

    @Parameter(title: "Location", description: "Optional storage location.", default: nil)
    var location: String?

    @Parameter(title: "Tags", description: "Optional tags describing the item.", default: nil)
    var tags: [String]?

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.addInventory(
            name: name,
            barcode: barcode,
            quantity: quantity,
            unit: unit,
            location: location,
            tags: tags
        )
        dependencies.services.events.post(kind: .inventoryAdded, payload: payload)
        return .result()
    }
}

@MainActor
struct AdjustInventoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust Inventory"
    static var description = IntentDescription("Adjust inventory levels by reference, name, or barcode.")

    static var parameterSummary: some ParameterSummary {
        Summary("Adjust \(\.$itemReference) by \(\.$deltaQuantity)")
    }

    @Parameter(title: "Item Reference", description: "An ID, name, or barcode for the inventory item.")
    var itemReference: String

    @Parameter(title: "Quantity Delta", description: "Positive or negative amount to adjust.")
    var deltaQuantity: Double

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.adjustInventory(
            itemReference: itemReference,
            deltaQuantity: deltaQuantity
        )
        dependencies.services.events.post(kind: .inventoryAdjusted, payload: payload)
        return .result()
    }
}

@MainActor
struct AddToShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Shopping List"
    static var description = IntentDescription("Add an item to a shopping list, creating the list if needed.")

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$quantity) of \(\.$itemIdentifier)") {
            When(\.$listName, .provided) {
                " to \(\.$listName)"
            }
        }
    }

    @Parameter(title: "Item", description: "Name, barcode, or identifier of the item to add.")
    var itemIdentifier: String

    @Parameter(title: "Quantity", description: "Desired quantity to purchase.")
    var quantity: Double

    @Parameter(title: "List Name", description: "Name of the shopping list.", default: nil)
    var listName: String?

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.addToShoppingList(
            itemIdentifier: itemIdentifier,
            quantity: quantity,
            listName: listName
        )
        dependencies.services.events.post(kind: .shoppingCreated, payload: payload)
        return .result()
    }
}

@MainActor
struct MarkBoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Bought"
    static var description = IntentDescription("Mark a shopping list line or entire list as purchased.")

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$reference) as bought")
    }

    @Parameter(title: "Reference", description: "Line ID or list name to mark as bought.")
    var reference: String

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.markBought(reference: reference)
        dependencies.services.events.post(kind: .shoppingChecked, payload: payload)
        return .result()
    }
}

@MainActor
struct StartHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Habit"
    static var description = IntentDescription("Start tracking a habit or update its target.")

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$habitReference)") {
            When(\.$target, .provided) {
                " with target \(\.$target)"
            }
        }
    }

    @Parameter(title: "Habit", description: "Habit identifier or name.")
    var habitReference: String

    @Parameter(title: "Target", description: "Optional target amount for the habit.", default: nil)
    var target: Double?

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.startHabit(
            habitReference: habitReference,
            target: target
        )
        dependencies.services.events.post(kind: .habitStarted, payload: payload)
        return .result()
    }
}

@MainActor
struct TickHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Tick Habit"
    static var description = IntentDescription("Register progress toward a habit goal.")

    static var parameterSummary: some ParameterSummary {
        Summary("Tick \(\.$habitReference)") {
            When(\.$amount, .provided) {
                " by \(\.$amount)"
            }
        }
    }

    @Parameter(title: "Habit", description: "Habit identifier or name to tick.")
    var habitReference: String

    @Parameter(title: "Amount", description: "Optional amount to apply.", default: nil)
    var amount: Double?

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.tickHabit(
            habitReference: habitReference,
            amount: amount
        )
        dependencies.services.events.post(kind: .habitTicked, payload: payload)
        return .result()
    }
}

@MainActor
struct WhatIsLowIntent: AppIntent {
    static var title: LocalizedStringResource = "What Is Low"
    static var description = IntentDescription("List inventory items that are at or below their restock threshold.")

    static var parameterSummary: some ParameterSummary {
        Summary("Show low stock items") {
            When(\.$stockFilter, .provided) {
                " matching \(\.$stockFilter)"
            }
        }
    }

    @Parameter(title: "Filter", description: "Optional filter to match item names.", default: nil)
    var stockFilter: String?

    func perform() async throws -> some IntentResult & ReturnsValue<[ItemSummary]> {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let result = try await useCases.whatIsLow(filter: stockFilter)
        dependencies.services.events.post(kind: .inventoryLow, payload: result.payload)
        return .result(value: result.items)
    }
}

@MainActor
struct ImportCSVIntent: AppIntent {
    static var title: LocalizedStringResource = "Import CSV"
    static var description = IntentDescription("Import inventory or transaction data from a CSV file.")

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$type) from \(\.$fileURL)")
    }

    @Parameter(title: "File", description: "The CSV file URL to import.")
    var fileURL: URL

    @Parameter(title: "Type", description: "Type of CSV to import (inventory or transactions).")
    var type: String

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.importCSV(fileURL: fileURL, type: type)
        dependencies.services.events.post(kind: .accountCsvImported, payload: payload)
        return .result()
    }
}

@MainActor
struct RunRuleIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Rule"
    static var description = IntentDescription("Execute an automation rule by name.")

    static var parameterSummary: some ParameterSummary {
        Summary("Run rule \(\.$ruleName)")
    }

    @Parameter(title: "Rule Name", description: "Name of the saved rule to execute.")
    var ruleName: String

    func perform() async throws -> some IntentResult {
        let dependencies = IntentDependencyContainer.shared
        let useCases = IntentUseCases(services: dependencies.services)
        let payload = try await useCases.runRule(named: ruleName)
        dependencies.services.events.post(kind: .ruleFired, payload: payload)
        return .result()
    }
}
