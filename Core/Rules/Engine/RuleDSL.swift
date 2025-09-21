import Foundation

public enum RuleTrigger: Equatable, Sendable {
    case timeAt(String)
    case geoEnter(String)
    case event(String)
    case inventoryBelowThreshold
}

public indirect enum RuleCondition: Equatable, Sendable {
    case and([RuleCondition])
    case or([RuleCondition])
    case not(RuleCondition)
    case eq(field: String, value: RuleValue)
    case lt(field: String, value: Double)
    case tagContains(String)
    case listHasOpenItems
}

public enum RuleAction: Equatable, Sendable {
    case notify(message: String)
    case shoppingAddMissingFromLowStock
    case transactionCreate(fromReceipt: Bool)
    case habitTick(name: String, amount: Double)
    case remindersCreate(title: String, dueISO8601: String)
    case calendarBlock(title: String, startISO8601: String, durationMinutes: Int)
}

public enum RuleValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
}

public struct RuleDefinition: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let trigger: RuleTrigger
    public let conditions: [RuleCondition]
    public let actions: [RuleAction]
    public let enabled: Bool

    public init(
        id: UUID,
        name: String,
        trigger: RuleTrigger,
        conditions: [RuleCondition],
        actions: [RuleAction],
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.enabled = enabled
    }
}

public struct RuleSnapshot: Equatable, Sendable {
    public var fields: [String: RuleValue]
    public var tags: Set<String>
    public var listHasOpenItems: Bool

    public init(
        fields: [String: RuleValue] = [:],
        tags: Set<String> = [],
        listHasOpenItems: Bool = false
    ) {
        self.fields = fields
        self.tags = tags
        self.listHasOpenItems = listHasOpenItems
    }

    public func value(for field: String) -> RuleValue? {
        fields[field]
    }
}

public enum TriggerEvent: Equatable, Sendable {
    case timeAt(String)
    case geoEnter(String)
    case event(String)
    case inventoryBelowThreshold
}

extension RuleTrigger {
    func matches(event: TriggerEvent) -> Bool {
        switch (self, event) {
        case let (.timeAt(expected), .timeAt(actual)):
            return expected == actual
        case let (.geoEnter(expected), .geoEnter(actual)):
            return expected == actual
        case let (.event(expected), .event(actual)):
            return expected == actual
        case (.inventoryBelowThreshold, .inventoryBelowThreshold):
            return true
        default:
            return false
        }
    }
}

extension RuleValue {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}
