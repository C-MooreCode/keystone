import Combine
import Foundation
import SwiftData

struct BudgetEnvelopeBreakdown: Identifiable, Equatable {
    let id: UUID
    let name: String
    let currency: String
    let limit: Decimal
    let spent: Decimal
    let remaining: Decimal
    let tags: [String]
    let notes: String?
}

struct BudgetSummary: Equatable {
    let currency: String
    let totalLimit: Decimal
    let totalSpent: Decimal
    let envelopes: [BudgetEnvelopeBreakdown]

    var totalRemaining: Decimal {
        totalLimit.currencySubtracting(totalSpent)
    }

    static func empty(currency: String = Locale.current.currency?.identifier ?? "USD") -> BudgetSummary {
        BudgetSummary(currency: currency, totalLimit: .zero, totalSpent: .zero, envelopes: [])
    }
}

@MainActor
final class BudgetPublisher {
    private let persistence: PersistenceController
    private let subject: CurrentValueSubject<BudgetSummary, Never>
    private let calendar: Calendar

    var publisher: AnyPublisher<BudgetSummary, Never> {
        subject.eraseToAnyPublisher()
    }

    init(persistence: PersistenceController, calendar: Calendar = .current) {
        self.persistence = persistence
        self.calendar = calendar
        self.subject = CurrentValueSubject(.empty())
    }

    func refresh() {
        do {
            subject.send(try loadSummary())
        } catch {
            assertionFailure("Failed to refresh budget summary: \(error)")
        }
    }

    private func loadSummary() throws -> BudgetSummary {
        let envelopes = try persistence.budgetEnvelopes.fetch(sortBy: [SortDescriptor(\.name, order: .forward)])
        guard !envelopes.isEmpty else {
            return .empty()
        }

        let currency = envelopes.first?.currency ?? Locale.current.currency?.identifier ?? "USD"
        let (startDate, endDate) = currentMonthBounds()

        let predicate = #Predicate<Transaction> { transaction in
            transaction.date >= startDate && transaction.date < endDate
        }
        let transactions = try persistence.transactions.fetch(predicate: predicate)

        let breakdowns: [BudgetEnvelopeBreakdown] = envelopes.map { envelope in
            let relevant = transactions.filter { transaction in
                guard transaction.currency.caseInsensitiveCompare(envelope.currency) == .orderedSame else { return false }
                guard !envelope.tags.isEmpty else { return false }
                let transactionTags = Set(transaction.tags.map { $0.lowercased() })
                let envelopeTags = Set(envelope.tags.map { $0.lowercased() })
                return !transactionTags.isDisjoint(with: envelopeTags)
            }
            let spent = CurrencyMath.sum(relevant.map(\.amount))
            return BudgetEnvelopeBreakdown(
                id: envelope.id,
                name: envelope.name,
                currency: envelope.currency,
                limit: envelope.monthlyLimit,
                spent: spent,
                remaining: envelope.monthlyLimit.currencySubtracting(spent),
                tags: envelope.tags,
                notes: envelope.notes
            )
        }

        let filteredBreakdowns = breakdowns.filter { _ in true }
        let totalLimit = CurrencyMath.sum(filteredBreakdowns.map(\.limit))
        let totalSpent = CurrencyMath.sum(filteredBreakdowns.map(\.spent))

        return BudgetSummary(
            currency: currency,
            totalLimit: totalLimit,
            totalSpent: totalSpent,
            envelopes: filteredBreakdowns
        )
    }

    private func currentMonthBounds() -> (Date, Date) {
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? now
        return (start, end)
    }
}
