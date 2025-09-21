import XCTest
@testable import RuleEngine

final class RuleEngineTests: XCTestCase {
    func testInventoryBelowThresholdAddsMissingItems() throws {
        let rule = RuleDefinition(
            id: UUID(),
            name: "Restock",
            trigger: .inventoryBelowThreshold,
            conditions: [],
            actions: [.shoppingAddMissingFromLowStock],
            enabled: true
        )

        let evaluator = RuleEvaluator()
        let actions = evaluator.evaluate(rule: rule, when: .inventoryBelowThreshold, snapshot: RuleSnapshot())
        XCTAssertEqual(actions, [.shoppingAddMissingFromLowStock])

        let services = TestServices()
        let executor = RuleExecutor(services: services.container, idempotencyGuard: services.idempotency)
        executor.execute(rule: rule, actions: actions)

        XCTAssertEqual(services.shopping.addMissingFromLowStockCallCount, 1)
    }

    func testReceiptScannedCreatesTransaction() throws {
        let rule = RuleDefinition(
            id: UUID(),
            name: "Log receipt",
            trigger: .event("receipt.scanned"),
            conditions: [],
            actions: [.transactionCreate(fromReceipt: true)],
            enabled: true
        )

        let evaluator = RuleEvaluator()
        let actions = evaluator.evaluate(rule: rule, when: .event("receipt.scanned"), snapshot: RuleSnapshot())
        XCTAssertEqual(actions, [.transactionCreate(fromReceipt: true)])

        let services = TestServices()
        let executor = RuleExecutor(services: services.container, idempotencyGuard: services.idempotency)
        executor.execute(rule: rule, actions: actions)

        XCTAssertEqual(services.transactions.createTransactionCalls, [.init(fromReceipt: true)])
    }
}

// MARK: - Test Helpers

private final class TestServices {
    let notifications = MockNotificationsService()
    let shopping = MockShoppingService()
    let transactions = MockTransactionsService()
    let habits = MockHabitsService()
    let reminders = MockRemindersService()
    let calendar = MockCalendarService()
    let idempotency = AlwaysAllowGuard()

    var container: RuleExecutionServices {
        RuleExecutionServices(
            notifications: notifications,
            shopping: shopping,
            transactions: transactions,
            habits: habits,
            reminders: reminders,
            calendar: calendar
        )
    }
}

private final class MockNotificationsService: NotificationService {
    func notify(message: String) {}
}

private final class MockShoppingService: ShoppingService {
    private(set) var addMissingFromLowStockCallCount = 0
    func addMissingFromLowStock() {
        addMissingFromLowStockCallCount += 1
    }
}

extension MockShoppingService: @unchecked Sendable {}

private struct TransactionCall: Equatable {
    let fromReceipt: Bool
}

private final class MockTransactionsService: TransactionsService {
    private(set) var createTransactionCalls: [TransactionCall] = []
    func createTransaction(fromReceipt: Bool) {
        createTransactionCalls.append(TransactionCall(fromReceipt: fromReceipt))
    }
}

extension MockTransactionsService: @unchecked Sendable {}

private final class MockHabitsService: HabitsService {
    func tickHabit(name: String, amount: Double) {}
}

private final class MockRemindersService: RemindersService {
    func createReminder(title: String, dueISO8601: String) {}
}

private final class MockCalendarService: CalendarService {
    func blockTime(title: String, startISO8601: String, durationMinutes: Int) {}
}

private final class AlwaysAllowGuard: RuleIdempotencyGuard {
    func shouldProceed(with ruleId: UUID) -> Bool { true }
}
