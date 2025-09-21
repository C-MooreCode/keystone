import SwiftUI
import WidgetKit

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let summary: TodaySummarySnapshot
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: Date(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        let summary = TodaySummaryStore().load() ?? .placeholder
        completion(TodayWidgetEntry(date: Date(), summary: summary))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let summary = TodaySummaryStore().load() ?? .placeholder
        let entry = TodayWidgetEntry(date: Date(), summary: summary)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct TodayWidgetEntryView: View {
    var entry: TodayWidgetEntry

    private var budgetPrimaryText: String {
        if let budget = entry.summary.budget {
            return budget.remainingFormatted
        }
        return "Set up budgets"
    }

    private var budgetSecondaryText: String? {
        entry.summary.budget.map { "of \($0.limitFormatted)" }
    }

    private var lowStockPrimary: String {
        let count = entry.summary.lowStockCount
        if count == 0 {
            return "All stocked"
        }
        return "\(count) low"
    }

    private var lowStockSecondary: String? {
        entry.summary.lowStockCount == 0 ? nil : "Needs review"
    }

    private var inboxPrimary: String {
        let count = entry.summary.inboxCount
        if count == 0 {
            return "Inbox zero"
        }
        return "\(count) waiting"
    }

    private var inboxSecondary: String? {
        entry.summary.inboxCount == 0 ? "You're caught up" : nil
    }

    private var calendarPrimary: String {
        entry.summary.calendar.displayTitle
    }

    private var calendarSecondary: String? {
        entry.summary.calendar.displaySubtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)

            deepLinkRow(tab: .expenses) {
                WidgetRow(
                    icon: "creditcard",
                    color: .green,
                    title: "Budget",
                    primary: budgetPrimaryText,
                    secondary: budgetSecondaryText
                )
            }

            deepLinkRow(tab: .inventory) {
                WidgetRow(
                    icon: "shippingbox",
                    color: .orange,
                    title: "Low stock",
                    primary: lowStockPrimary,
                    secondary: lowStockSecondary
                )
            }

            deepLinkRow(tab: .today) {
                WidgetRow(
                    icon: "calendar",
                    color: .blue,
                    title: "Next block",
                    primary: calendarPrimary,
                    secondary: calendarSecondary
                )
            }

            deepLinkRow(tab: .habits) {
                HabitsWidgetRow(habits: entry.summary.habits)
            }

            deepLinkRow(tab: .inbox) {
                WidgetRow(
                    icon: "tray",
                    color: .teal,
                    title: "Inbox",
                    primary: inboxPrimary,
                    secondary: inboxSecondary
                )
            }
        }
        .padding()
        .widgetBackground()
        .widgetURL(AppDeepLink.tab(.today).url)
    }

    @ViewBuilder
    private func deepLinkRow<Content: View>(tab: AppState.Tab, @ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            Link(destination: AppDeepLink.tab(tab).url) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct WidgetRow: View {
    let icon: String
    let color: Color
    let title: String
    let primary: String
    let secondary: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(color.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let secondary {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct HabitsWidgetRow: View {
    let habits: [TodaySummarySnapshot.Habit]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetRow(
                icon: "repeat",
                color: .purple,
                title: "Habits",
                primary: habitsPrimaryText,
                secondary: habitsSecondaryText
            )

            if !habits.isEmpty {
                ForEach(habits.prefix(2)) { habit in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: habit.isCompletedToday ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(habit.isCompletedToday ? Color.green : Color.gray)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(habit.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(habit.statusDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var habitsPrimaryText: String {
        if habits.isEmpty {
            return "No habits yet"
        }
        let completed = habits.filter(\.isCompletedToday).count
        return "\(completed)/\(habits.count) complete"
    }

    private var habitsSecondaryText: String? {
        if habits.isEmpty { return "Add routines" }
        return nil
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, macOSApplicationExtension 14.0, *) {
            containerBackground(for: .widget) {
                Color.clear
            }
        } else {
            background(Color(.systemBackground))
        }
    }
}

struct KeystoneTodayWidget: Widget {
    let kind: String = TodaySummaryStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Budget, inventory, habits, and inbox at a glance.")
    }
}

#Preview(as: .systemMedium) {
    KeystoneTodayWidget()
} timeline: {
    TodayWidgetEntry(date: .now, summary: .placeholder)
}
