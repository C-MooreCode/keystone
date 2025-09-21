import Foundation

struct TodaySummarySnapshot: Codable, Equatable {
    struct Budget: Codable, Equatable {
        var limit: DecimalCodable
        var spent: DecimalCodable
        var remaining: DecimalCodable
        var currency: String

        init(limit: Decimal, spent: Decimal, remaining: Decimal, currency: String) {
            self.limit = DecimalCodable(limit)
            self.spent = DecimalCodable(spent)
            self.remaining = DecimalCodable(remaining)
            self.currency = currency
        }

        init(summary: BudgetSummary) {
            self.init(
                limit: summary.totalLimit,
                spent: summary.totalSpent,
                remaining: summary.totalRemaining,
                currency: summary.currency
            )
        }

        var remainingFormatted: String {
            formatCurrency(remaining.value)
        }

        var limitFormatted: String {
            formatCurrency(limit.value)
        }

        var spentFormatted: String {
            formatCurrency(spent.value)
        }

        var progress: Double {
            let limitValue = limit.value
            guard limitValue > .zero else { return 0 }
            let spentValue = spent.value
            let ratio = spentValue.currencyDividing(by: limitValue, scale: 4)
            return min(max(NSDecimalNumber(decimal: ratio).doubleValue, 0), 1)
        }

        private func formatCurrency(_ value: Decimal) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currency
            formatter.locale = Locale.current
            return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        }
    }

    struct Habit: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let schedule: String
        let streak: Int
        let lastCheckIn: Date?

        init(id: UUID, name: String, schedule: String, streak: Int, lastCheckIn: Date?) {
            self.id = id
            self.name = name
            self.schedule = schedule
            self.streak = streak
            self.lastCheckIn = lastCheckIn
        }

        var isCompletedToday: Bool {
            guard let lastCheckIn else { return false }
            return Calendar.current.isDateInToday(lastCheckIn)
        }

        var streakDisplay: String {
            "🔥 \(streak)"
        }

        var statusDescription: String {
            isCompletedToday ? "Completed today" : "Pending"
        }
    }

    struct Calendar: Codable, Equatable {
        enum State: String, Codable {
            case loading
            case needsPermission
            case notLinked
            case noUpcoming
            case event
        }

        var state: State
        var title: String?
        var startDate: Date?
        var endDate: Date?
        var location: String?

        init(state: State, title: String? = nil, startDate: Date? = nil, endDate: Date? = nil, location: String? = nil) {
            self.state = state
            self.title = title
            self.startDate = startDate
            self.endDate = endDate
            self.location = location
        }

        var displayTitle: String {
            switch state {
            case .loading:
                return "Updating…"
            case .needsPermission:
                return "Allow calendar access"
            case .notLinked:
                return "Link a calendar"
            case .noUpcoming:
                return "No upcoming events"
            case .event:
                return title?.isEmpty == false ? title! : "Upcoming event"
            }
        }

        var displaySubtitle: String? {
            switch state {
            case .loading:
                return "Fetching your schedule"
            case .needsPermission:
                return "Grant permission in Settings"
            case .notLinked:
                return "Connect via Calendar Links"
            case .noUpcoming:
                return "You're all caught up"
            case .event:
                return formattedEventWindow()
            }
        }

        var displayFootnote: String? {
            guard state == .event else { return nil }
            return location
        }

        private func formattedEventWindow() -> String? {
            guard let startDate else { return nil }
            let calendar = Calendar.current
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.dateStyle = .none

            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE, MMM d"

            let dateTimeFormatter = DateFormatter()
            dateTimeFormatter.dateStyle = .short
            dateTimeFormatter.timeStyle = .short

            if let endDate {
                if calendar.isDate(startDate, inSameDayAs: endDate) {
                    let startPrefix: String
                    if calendar.isDateInToday(startDate) {
                        startPrefix = "Today"
                    } else if calendar.isDateInTomorrow(startDate) {
                        startPrefix = "Tomorrow"
                    } else {
                        startPrefix = dayFormatter.string(from: startDate)
                    }
                    return "\(startPrefix) \(timeFormatter.string(from: startDate)) – \(timeFormatter.string(from: endDate))"
                } else {
                    return "\(dateTimeFormatter.string(from: startDate)) – \(dateTimeFormatter.string(from: endDate))"
                }
            } else {
                if Calendar.current.isDateInToday(startDate) {
                    return "Today \(timeFormatter.string(from: startDate))"
                } else if Calendar.current.isDateInTomorrow(startDate) {
                    return "Tomorrow \(timeFormatter.string(from: startDate))"
                }
                return dateTimeFormatter.string(from: startDate)
            }
        }
    }

    var generatedAt: Date
    var budget: Budget?
    var lowStockCount: Int
    var calendar: Calendar
    var habits: [Habit]
    var inboxCount: Int

    init(
        generatedAt: Date = Date(),
        budget: Budget? = nil,
        lowStockCount: Int = 0,
        calendar: Calendar = Calendar(state: .loading),
        habits: [Habit] = [],
        inboxCount: Int = 0
    ) {
        self.generatedAt = generatedAt
        self.budget = budget
        self.lowStockCount = lowStockCount
        self.calendar = calendar
        self.habits = habits
        self.inboxCount = inboxCount
    }

    static var placeholder: TodaySummarySnapshot {
        TodaySummarySnapshot(
            generatedAt: Date(),
            budget: Budget(limit: 500, spent: 320, remaining: 180, currency: Locale.current.currency?.identifier ?? "USD"),
            lowStockCount: 3,
            calendar: Calendar(
                state: .event,
                title: "Weekly planning",
                startDate: Calendar.current.date(byAdding: .hour, value: 1, to: Date()),
                endDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
                location: "Office"
            ),
            habits: [
                Habit(id: UUID(), name: "Morning stretch", schedule: "Every day", streak: 4, lastCheckIn: Date()),
                Habit(id: UUID(), name: "Read 20 pages", schedule: "Weekdays", streak: 2, lastCheckIn: nil)
            ],
            inboxCount: 5
        )
    }
}

struct DecimalCodable: Codable, Equatable {
    var value: Decimal

    init(_ value: Decimal) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid decimal string: \(string)")
        }
        self.value = decimal
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        container.encode(NSDecimalNumber(decimal: value).stringValue)
    }
}
