import Foundation

extension RuleSpec {
    func toRuleDefinition(codec: RuleSpecCodec = RuleSpecCodec()) throws -> RuleDefinition {
        let payload = RuleSpecPayload(
            id: id,
            name: name,
            trigger: trigger,
            conditions: conditions,
            actions: actions,
            enabled: enabled
        )
        return try codec.decode(payload: payload)
    }

    static func from(rule: RuleDefinition, codec: RuleSpecCodec = RuleSpecCodec()) throws -> RuleSpec {
        let payload = try codec.encode(rule)
        return try RuleSpec(
            id: payload.id,
            name: payload.name,
            trigger: payload.trigger,
            conditions: payload.conditions,
            actions: payload.actions,
            enabled: payload.enabled
        )
    }
}
