import Foundation

public struct RuleEvaluator: Sendable {
    public init() {}

    public func evaluate(rule: RuleDefinition, when event: TriggerEvent, snapshot: RuleSnapshot) -> [RuleAction] {
        guard rule.enabled else { return [] }
        guard rule.trigger.matches(event: event) else { return [] }

        let conditionsSatisfied = rule.conditions.allSatisfy { condition in
            evaluate(condition, with: snapshot)
        }

        return conditionsSatisfied ? rule.actions : []
    }

    private func evaluate(_ condition: RuleCondition, with snapshot: RuleSnapshot) -> Bool {
        switch condition {
        case let .and(conditions):
            return conditions.allSatisfy { evaluate($0, with: snapshot) }
        case let .or(conditions):
            return conditions.contains { evaluate($0, with: snapshot) }
        case let .not(condition):
            return !evaluate(condition, with: snapshot)
        case let .eq(field, value):
            guard let fieldValue = snapshot.value(for: field) else { return false }
            return fieldValue == value
        case let .lt(field, value):
            guard let fieldValue = snapshot.value(for: field)?.numberValue else { return false }
            return fieldValue < value
        case let .tagContains(tag):
            return snapshot.tags.contains(tag)
        case .listHasOpenItems:
            return snapshot.listHasOpenItems
        }
    }
}
