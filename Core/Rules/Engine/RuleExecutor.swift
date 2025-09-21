import Foundation

public protocol NotificationService: Sendable {
    func notify(message: String)
}

public protocol ShoppingService: Sendable {
    func addMissingFromLowStock()
}

public protocol TransactionsService: Sendable {
    func createTransaction(fromReceipt: Bool)
}

public protocol HabitsService: Sendable {
    func tickHabit(name: String, amount: Double)
}

public protocol RemindersService: Sendable {
    func createReminder(title: String, dueISO8601: String)
}

public protocol CalendarService: Sendable {
    func blockTime(title: String, startISO8601: String, durationMinutes: Int)
}

public protocol RuleIdempotencyGuard: Sendable {
    func shouldProceed(with ruleId: UUID) -> Bool
}

public struct RuleExecutionServices: Sendable {
    public var notifications: NotificationService
    public var shopping: ShoppingService
    public var transactions: TransactionsService
    public var habits: HabitsService
    public var reminders: RemindersService
    public var calendar: CalendarService

    public init(
        notifications: NotificationService,
        shopping: ShoppingService,
        transactions: TransactionsService,
        habits: HabitsService,
        reminders: RemindersService,
        calendar: CalendarService
    ) {
        self.notifications = notifications
        self.shopping = shopping
        self.transactions = transactions
        self.habits = habits
        self.reminders = reminders
        self.calendar = calendar
    }
}

public struct RuleExecutor: Sendable {
    private let services: RuleExecutionServices
    private let idempotencyGuard: RuleIdempotencyGuard

    public init(services: RuleExecutionServices, idempotencyGuard: RuleIdempotencyGuard) {
        self.services = services
        self.idempotencyGuard = idempotencyGuard
    }

    public func execute(rule: RuleDefinition, actions: [RuleAction]) {
        guard !actions.isEmpty else { return }
        guard idempotencyGuard.shouldProceed(with: rule.id) else { return }

        for action in actions {
            switch action {
            case let .notify(message):
                services.notifications.notify(message: message)
            case .shoppingAddMissingFromLowStock:
                services.shopping.addMissingFromLowStock()
            case let .transactionCreate(fromReceipt):
                services.transactions.createTransaction(fromReceipt: fromReceipt)
            case let .habitTick(name, amount):
                services.habits.tickHabit(name: name, amount: amount)
            case let .remindersCreate(title, dueISO8601):
                services.reminders.createReminder(title: title, dueISO8601: dueISO8601)
            case let .calendarBlock(title, startISO8601, durationMinutes):
                services.calendar.blockTime(title: title, startISO8601: startISO8601, durationMinutes: durationMinutes)
            }
        }
    }
}

public final class InMemoryRuleIdempotencyGuard: RuleIdempotencyGuard {
    private let ttl: TimeInterval
    private let dateProvider: @Sendable () -> Date
    private var expiryDates: [UUID: Date]
    private let queue = DispatchQueue(label: "RuleIdempotencyGuard")

    public init(ttl: TimeInterval = 30, dateProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.dateProvider = dateProvider
        self.expiryDates = [:]
    }

    public func shouldProceed(with ruleId: UUID) -> Bool {
        queue.sync {
            let now = dateProvider()
            expiryDates = expiryDates.filter { $0.value > now }
            if let expiry = expiryDates[ruleId], expiry > now {
                return false
            }

            expiryDates[ruleId] = now.addingTimeInterval(ttl)
            return true
        }
    }
}

extension InMemoryRuleIdempotencyGuard: @unchecked Sendable {}
