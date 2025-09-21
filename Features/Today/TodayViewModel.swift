import Combine
import EventKit
import Foundation
import SwiftData

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var summary: TodaySummarySnapshot
    @Published var isLoading = false

    private var services: ServiceContainer?
    private var cancellables: Set<AnyCancellable> = []
    private let calendarStore = EKEventStore()
    private let summaryStore: TodaySummaryStore
    private var currentSummary: TodaySummarySnapshot

    init(summaryStore: TodaySummaryStore = TodaySummaryStore()) {
        let initialSummary = summaryStore.load() ?? .placeholder
        self.summaryStore = summaryStore
        self.summary = initialSummary
        self.currentSummary = initialSummary
    }

    func configure(services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services

        services.budgetPublisher.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                self?.applySummaryUpdate { snapshot in
                    snapshot.budget = TodaySummarySnapshot.Budget(summary: summary)
                }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        guard let services else { return }
        isLoading = true
        services.budgetPublisher.refresh()

        Task {
            let lowStockItems = loadLowStock(using: services)
            let habits = loadHabits(using: services)
            let inbox = loadInbox(using: services)
            let calendar = await loadCalendar(using: services)

            await MainActor.run {
                self.applySummaryUpdate { snapshot in
                    snapshot.lowStockCount = lowStockItems.count
                    snapshot.lowStockItems = lowStockItems
                    snapshot.habits = habits
                    snapshot.inboxCount = inbox
                    snapshot.calendar = calendar
                }
                self.isLoading = false
            }
        }
    }

    private func applySummaryUpdate(_ update: (inout TodaySummarySnapshot) -> Void) {
        update(&currentSummary)
        currentSummary.generatedAt = Date()
        summary = currentSummary
        summaryStore.save(currentSummary)
    }

    private func loadLowStock(using services: ServiceContainer) -> [TodaySummarySnapshot.LowStockItem] {
        do {
            let items = try services.persistence.inventoryItems.fetch()
            let lowStock = items.compactMap { item -> TodaySummarySnapshot.LowStockItem? in
                let threshold = NSDecimalNumber(decimal: item.restockThreshold).doubleValue
                guard threshold > 0, item.qty <= threshold else { return nil }
                return TodaySummarySnapshot.LowStockItem(
                    id: item.id,
                    name: item.name,
                    quantity: item.qty,
                    threshold: threshold,
                    unit: item.unit
                )
            }

            let sorted = lowStock.sorted { lhs, rhs in
                let lhsRatio = lhs.threshold > 0 ? lhs.quantity / lhs.threshold : Double.greatestFiniteMagnitude
                let rhsRatio = rhs.threshold > 0 ? rhs.quantity / rhs.threshold : Double.greatestFiniteMagnitude
                if lhsRatio != rhsRatio {
                    return lhsRatio < rhsRatio
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return Array(sorted.prefix(20))
        } catch {
            return summary.lowStockItems
        }
    }

    private func loadHabits(using services: ServiceContainer) -> [TodaySummarySnapshot.Habit] {
        do {
            let models = try services.persistence.habits.fetch(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )

            let sorted = models.sorted { lhs, rhs in
                let lhsComplete = lhs.lastCheckIn.map { Calendar.current.isDateInToday($0) } ?? false
                let rhsComplete = rhs.lastCheckIn.map { Calendar.current.isDateInToday($0) } ?? false
                if lhsComplete != rhsComplete {
                    return !lhsComplete && rhsComplete
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return Array(sorted.prefix(2)).map { model in
                TodaySummarySnapshot.Habit(
                    id: model.id,
                    name: model.name,
                    schedule: model.scheduleRule,
                    streak: model.streak,
                    lastCheckIn: model.lastCheckIn
                )
            }
        } catch {
            return summary.habits
        }
    }

    private func loadInbox(using services: ServiceContainer) -> Int {
        do {
            let predicate = #Predicate<EventRecord> { record in
                record.kind == DomainEventKind.inboxEnqueued.rawValue
            }
            let records = try services.persistence.eventStore.fetch(predicate: predicate)
            return records.count
        } catch {
            return summary.inboxCount
        }
    }

    private func loadCalendar(using services: ServiceContainer) async -> TodaySummarySnapshot.Calendar {
        let status = EKEventStore.authorizationStatus(for: .event)

        if #available(iOS 17.0, macOS 14.0, *) {
            switch status {
            case .fullAccess, .authorized:
                break
            case .notDetermined:
                guard await requestCalendarAccess() else {
                    return TodaySummarySnapshot.Calendar(state: .needsPermission)
                }
            default:
                return TodaySummarySnapshot.Calendar(state: .needsPermission)
            }
        } else {
            switch status {
            case .authorized:
                break
            case .notDetermined:
                guard await requestCalendarAccess() else {
                    return TodaySummarySnapshot.Calendar(state: .needsPermission)
                }
            default:
                return TodaySummarySnapshot.Calendar(state: .needsPermission)
            }
        }

        do {
            let links = try services.persistence.calendarLinks.fetch()
            guard !links.isEmpty else {
                return TodaySummarySnapshot.Calendar(state: .notLinked)
            }

            let events = links.compactMap { link in
                calendarStore.event(withIdentifier: link.eventIdentifier)
            }

            guard !events.isEmpty else {
                return TodaySummarySnapshot.Calendar(state: .noUpcoming)
            }

            let now = Date()
            let upcoming = events
                .compactMap { event -> (Date, EKEvent)? in
                    let start = event.startDate ?? event.endDate
                    guard let comparisonDate = start else { return nil }
                    let end = event.endDate ?? comparisonDate
                    if end < now { return nil }
                    return (comparisonDate, event)
                }
                .sorted { $0.0 < $1.0 }
                .first?.1

            guard let event = upcoming else {
                return TodaySummarySnapshot.Calendar(state: .noUpcoming)
            }

            return TodaySummarySnapshot.Calendar(
                state: .event,
                title: sanitize(event.title) ?? "Upcoming event",
                startDate: event.startDate,
                endDate: event.endDate,
                location: sanitize(event.location)
            )
        } catch {
            return TodaySummarySnapshot.Calendar(state: .noUpcoming)
        }
    }

    private func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            do {
                return try await calendarStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                calendarStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func sanitize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
