import Foundation
import CoreFoundation

public struct RuleSpecPayload: Sendable {
    public var id: UUID
    public var name: String
    public var trigger: String
    public var conditions: [String]
    public var actions: [String]
    public var enabled: Bool

    public init(id: UUID, name: String, trigger: String, conditions: [String], actions: [String], enabled: Bool) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.enabled = enabled
    }
}

public enum RuleSpecCodecError: Error, Equatable {
    case invalidJSON
    case invalidFunction(String)
    case invalidArguments(String)
    case unsupportedValue(String)
}

public struct RuleSpecCodec: Sendable {
    public init() {}

    public func decode(payload: RuleSpecPayload) throws -> RuleDefinition {
        let trigger = try decodeTrigger(from: payload.trigger)
        let conditions = try payload.conditions.map(decodeCondition)
        let actions = try payload.actions.map(decodeAction)
        return RuleDefinition(
            id: payload.id,
            name: payload.name,
            trigger: trigger,
            conditions: conditions,
            actions: actions,
            enabled: payload.enabled
        )
    }

    public func encode(_ rule: RuleDefinition) throws -> RuleSpecPayload {
        let trigger = try encode(trigger: rule.trigger)
        let conditions = try rule.conditions.map(encode(condition:))
        let actions = try rule.actions.map(encode(action:))
        return RuleSpecPayload(
            id: rule.id,
            name: rule.name,
            trigger: trigger,
            conditions: conditions,
            actions: actions,
            enabled: rule.enabled
        )
    }

    // MARK: - Trigger

    private func decodeTrigger(from json: String) throws -> RuleTrigger {
        let expression = try decodeExpression(from: json)
        guard case let .function(name, arguments) = expression else {
            throw RuleSpecCodecError.invalidFunction("Trigger must be a function")
        }

        switch name {
        case "time.at":
            let value = try arguments.expectSingleValue().requireString()
            return .timeAt(value)
        case "geo.enter":
            let value = try arguments.expectSingleValue().requireString()
            return .geoEnter(value)
        case "event":
            let value = try arguments.expectSingleValue().requireString()
            return .event(value)
        case "inventory.belowThreshold":
            guard arguments.isEmpty else {
                throw RuleSpecCodecError.invalidArguments("inventory.belowThreshold does not accept arguments")
            }
            return .inventoryBelowThreshold
        default:
            throw RuleSpecCodecError.invalidFunction("Unknown trigger: \(name)")
        }
    }

    private func encode(trigger: RuleTrigger) throws -> String {
        let expression: DSLExpression
        switch trigger {
        case let .timeAt(value):
            expression = .function(name: "time.at", arguments: [.value(.string(value))])
        case let .geoEnter(value):
            expression = .function(name: "geo.enter", arguments: [.value(.string(value))])
        case let .event(value):
            expression = .function(name: "event", arguments: [.value(.string(value))])
        case .inventoryBelowThreshold:
            expression = .function(name: "inventory.belowThreshold", arguments: [])
        }
        return try encode(expression: expression)
    }

    // MARK: - Conditions

    private func decodeCondition(from json: String) throws -> RuleCondition {
        let expression = try decodeExpression(from: json)
        return try decodeCondition(from: expression)
    }

    private func decodeCondition(from expression: DSLExpression) throws -> RuleCondition {
        guard case let .function(name, arguments) = expression else {
            throw RuleSpecCodecError.invalidFunction("Condition must be a function")
        }

        switch name {
        case "and":
            let conditions = try arguments.map { try decodeCondition(from: $0) }
            return .and(conditions)
        case "or":
            let conditions = try arguments.map { try decodeCondition(from: $0) }
            return .or(conditions)
        case "not":
            let condition = try arguments.expectSingleFunction()
            return .not(try decodeCondition(from: condition))
        case "eq":
            guard arguments.count == 2 else {
                throw RuleSpecCodecError.invalidArguments("eq requires 2 arguments")
            }
            let field = try arguments[0].requireString()
            let value = try arguments[1].requireRuleValue()
            return .eq(field: field, value: value)
        case "lt":
            guard arguments.count == 2 else {
                throw RuleSpecCodecError.invalidArguments("lt requires 2 arguments")
            }
            let field = try arguments[0].requireString()
            guard case let .number(number) = try arguments[1].requireRuleValue() else {
                throw RuleSpecCodecError.invalidArguments("lt requires a numeric value")
            }
            return .lt(field: field, value: number)
        case "tagContains":
            let tag = try arguments.expectSingleValue().requireString()
            return .tagContains(tag)
        case "listHasOpenItems":
            guard arguments.isEmpty else {
                throw RuleSpecCodecError.invalidArguments("listHasOpenItems does not accept arguments")
            }
            return .listHasOpenItems
        default:
            throw RuleSpecCodecError.invalidFunction("Unknown condition: \(name)")
        }
    }

    private func encode(condition: RuleCondition) throws -> String {
        let expression = try encodeConditionExpression(condition)
        return try encode(expression: expression)
    }

    private func encodeConditionExpression(_ condition: RuleCondition) throws -> DSLExpression {
        switch condition {
        case let .and(conditions):
            return .function(name: "and", arguments: try conditions.map { try encodeConditionExpression($0) })
        case let .or(conditions):
            return .function(name: "or", arguments: try conditions.map { try encodeConditionExpression($0) })
        case let .not(condition):
            return .function(name: "not", arguments: [try encodeConditionExpression(condition)])
        case let .eq(field, value):
            return .function(name: "eq", arguments: [.value(.string(field)), .value(value)])
        case let .lt(field, value):
            return .function(name: "lt", arguments: [.value(.string(field)), .value(.number(value))])
        case let .tagContains(tag):
            return .function(name: "tagContains", arguments: [.value(.string(tag))])
        case .listHasOpenItems:
            return .function(name: "listHasOpenItems", arguments: [])
        }
    }

    // MARK: - Actions

    private func decodeAction(from json: String) throws -> RuleAction {
        let expression = try decodeExpression(from: json)
        guard case let .function(name, arguments) = expression else {
            throw RuleSpecCodecError.invalidFunction("Action must be a function")
        }

        switch name {
        case "notify":
            let message = try arguments.expectSingleValue().requireString()
            return .notify(message: message)
        case "shopping.addMissingFromLowStock":
            guard arguments.isEmpty else {
                throw RuleSpecCodecError.invalidArguments("shopping.addMissingFromLowStock does not accept arguments")
            }
            return .shoppingAddMissingFromLowStock
        case "transaction.create":
            guard arguments.count == 1 else {
                throw RuleSpecCodecError.invalidArguments("transaction.create requires 1 argument")
            }
            guard case let .bool(fromReceipt) = try arguments[0].requireRuleValue() else {
                throw RuleSpecCodecError.invalidArguments("transaction.create expects a boolean")
            }
            return .transactionCreate(fromReceipt: fromReceipt)
        case "habit.tick":
            guard arguments.count == 2 else {
                throw RuleSpecCodecError.invalidArguments("habit.tick requires 2 arguments")
            }
            let name = try arguments[0].requireString()
            guard case let .number(amount) = try arguments[1].requireRuleValue() else {
                throw RuleSpecCodecError.invalidArguments("habit.tick amount must be numeric")
            }
            return .habitTick(name: name, amount: amount)
        case "reminders.create":
            guard arguments.count == 2 else {
                throw RuleSpecCodecError.invalidArguments("reminders.create requires 2 arguments")
            }
            let title = try arguments[0].requireString()
            let due = try arguments[1].requireString()
            return .remindersCreate(title: title, dueISO8601: due)
        case "calendar.block":
            guard arguments.count == 3 else {
                throw RuleSpecCodecError.invalidArguments("calendar.block requires 3 arguments")
            }
            let title = try arguments[0].requireString()
            let start = try arguments[1].requireString()
            guard case let .number(duration) = try arguments[2].requireRuleValue() else {
                throw RuleSpecCodecError.invalidArguments("calendar.block duration must be numeric")
            }
            return .calendarBlock(title: title, startISO8601: start, durationMinutes: Int(duration))
        default:
            throw RuleSpecCodecError.invalidFunction("Unknown action: \(name)")
        }
    }

    private func encode(action: RuleAction) throws -> String {
        let expression: DSLExpression
        switch action {
        case let .notify(message):
            expression = .function(name: "notify", arguments: [.value(.string(message))])
        case .shoppingAddMissingFromLowStock:
            expression = .function(name: "shopping.addMissingFromLowStock", arguments: [])
        case let .transactionCreate(fromReceipt):
            expression = .function(name: "transaction.create", arguments: [.value(.bool(fromReceipt))])
        case let .habitTick(name, amount):
            expression = .function(name: "habit.tick", arguments: [.value(.string(name)), .value(.number(amount))])
        case let .remindersCreate(title, dueISO8601):
            expression = .function(name: "reminders.create", arguments: [.value(.string(title)), .value(.string(dueISO8601))])
        case let .calendarBlock(title, startISO8601, durationMinutes):
            expression = .function(
                name: "calendar.block",
                arguments: [
                    .value(.string(title)),
                    .value(.string(startISO8601)),
                    .value(.number(Double(durationMinutes)))
                ]
            )
        }
        return try encode(expression: expression)
    }

    // MARK: - Expression Helpers

    private func decodeExpression(from json: String) throws -> DSLExpression {
        guard let data = json.data(using: .utf8) else { throw RuleSpecCodecError.invalidJSON }
        let raw = try JSONSerialization.jsonObject(with: data)
        return try DSLExpression.from(raw: raw)
    }

    private func encode(expression: DSLExpression) throws -> String {
        let raw = try expression.toRaw()
        guard JSONSerialization.isValidJSONObject(raw) else {
            throw RuleSpecCodecError.invalidJSON
        }
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw RuleSpecCodecError.invalidJSON
        }
        return string
    }
}

// MARK: - DSLExpression

private enum DSLExpression: Sendable {
    case function(name: String, arguments: [DSLExpression])
    case value(RuleValue)

    static func from(raw: Any) throws -> DSLExpression {
        if let array = raw as? [Any] {
            guard let first = array.first as? String else {
                throw RuleSpecCodecError.invalidFunction("Function name missing")
            }
            let arguments = try array.dropFirst().map { try DSLExpression.from(raw: $0) }
            return .function(name: first, arguments: arguments)
        }

        if let string = raw as? String {
            return .value(.string(string))
        }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .value(.bool(number.boolValue))
            } else {
                return .value(.number(number.doubleValue))
            }
        }

        throw RuleSpecCodecError.unsupportedValue("Unsupported literal: \(raw)")
    }

    func toRaw() throws -> Any {
        switch self {
        case let .function(name, arguments):
            var array: [Any] = [name]
            for argument in arguments {
                array.append(try argument.toRaw())
            }
            return array
        case let .value(value):
            switch value {
            case let .string(string):
                return string
            case let .number(number):
                return number
            case let .bool(bool):
                return bool
            }
        }
    }
}

private extension Array where Element == DSLExpression {
    func expectSingleValue() throws -> DSLExpression {
        guard count == 1 else {
            throw RuleSpecCodecError.invalidArguments("Expected a single argument")
        }
        return self[0]
    }

    func expectSingleFunction() throws -> DSLExpression {
        let expression = try expectSingleValue()
        guard case .function = expression else {
            throw RuleSpecCodecError.invalidArguments("Expected a condition function")
        }
        return expression
    }
}

private extension DSLExpression {
    func requireString() throws -> String {
        guard case let .value(value) = self, case let .string(string) = value else {
            throw RuleSpecCodecError.invalidArguments("Expected string literal")
        }
        return string
    }

    func requireRuleValue() throws -> RuleValue {
        guard case let .value(value) = self else {
            throw RuleSpecCodecError.invalidArguments("Expected literal value")
        }
        return value
    }
}
