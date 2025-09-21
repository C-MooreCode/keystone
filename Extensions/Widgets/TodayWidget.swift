import SwiftUI
import WidgetKit

struct TodaySummaryEntry: TimelineEntry {
    let date: Date
    let summary: TodaySummarySnapshot
}

struct TodaySummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodaySummaryEntry {
        TodaySummaryEntry(date: Date(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaySummaryEntry) -> Void) {
        let summary = TodaySummaryStore().load() ?? .placeholder
        completion(TodaySummaryEntry(date: Date(), summary: summary))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaySummaryEntry>) -> Void) {
        let summary = TodaySummaryStore().load() ?? .placeholder
        let entry = TodaySummaryEntry(date: Date(), summary: summary)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct TodaySummaryWidgetView: View {
    let entry: TodaySummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            deepLink(tab: .expenses) {
                BudgetSummaryCard(budget: entry.summary.budget)
            }

            deepLink(tab: .inventory) {
                LowStockSummaryCard(count: entry.summary.lowStockCount)
            }

            HabitButtonsView(habits: entry.summary.habits)
        }
        .padding()
        .widgetBackground()
        .widgetURL(AppDeepLink.tab(.today).url)
    }

    @ViewBuilder
    private func deepLink(tab: AppState.Tab, @ViewBuilder content: () -> some View) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            Link(destination: AppDeepLink.tab(tab).url) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct BudgetSummaryCard: View {
    let budget: TodaySummarySnapshot.Budget?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "creditcard")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Budget left")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let budget {
                    Text(budget.remainingFormatted)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("of \(budget.limitFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: budget.progress)
                        .progressViewStyle(.linear)
                } else {
                    Text("Set up budgets")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Track your spending limits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LowStockSummaryCard: View {
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Low stock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(primaryText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryText: String {
        if count == 0 {
            return "All stocked"
        }
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    private var detailText: String? {
        count == 0 ? "Nothing needs attention" : "Tap to review inventory"
    }
}

private struct HabitButtonsView: View {
    let habits: [TodaySummarySnapshot.Habit]

    private var displayedHabits: [TodaySummarySnapshot.Habit] {
        Array(habits.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Habits")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(displayedHabits) { habit in
                    HabitQuickAction(habit: habit)
                }

                if displayedHabits.count < 2 {
                    for index in displayedHabits.count..<2 {
                        AddHabitQuickAction(isEmptyState: displayedHabits.isEmpty && index == 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HabitQuickAction: View {
    let habit: TodaySummarySnapshot.Habit

    var body: some View {
        Link(destination: AppDeepLink.tab(.habits).url) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: habit.isCompletedToday ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(habit.isCompletedToday ? Color.green : Color.secondary)
                    Text(habit.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(habit.statusDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.purple.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AddHabitQuickAction: View {
    let isEmptyState: Bool

    var body: some View {
        Link(destination: AppDeepLink.tab(.habits).url) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(Color.purple)
                    Text(isEmptyState ? "Add a habit" : "More habits")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text("Open the Habits tab")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.purple.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

struct LowStockWidgetEntry: TimelineEntry {
    let date: Date
    let items: [TodaySummarySnapshot.LowStockItem]
}

struct LowStockWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LowStockWidgetEntry {
        LowStockWidgetEntry(date: Date(), items: TodaySummarySnapshot.placeholder.lowStockItems)
    }

    func getSnapshot(in context: Context, completion: @escaping (LowStockWidgetEntry) -> Void) {
        let summary = TodaySummaryStore().load() ?? .placeholder
        completion(LowStockWidgetEntry(date: Date(), items: summary.lowStockItems))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LowStockWidgetEntry>) -> Void) {
        let summary = TodaySummaryStore().load() ?? .placeholder
        let entry = LowStockWidgetEntry(date: Date(), items: summary.lowStockItems)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct LowStockWidgetView: View {
    let entry: LowStockWidgetEntry

    private var displayedItems: [TodaySummarySnapshot.LowStockItem] {
        Array(entry.items.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Low stock")
                .font(.headline)

            if displayedItems.isEmpty {
                Text("All items are above their thresholds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedItems) { item in
                    LowStockRow(item: item)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .widgetBackground()
        .widgetURL(AppDeepLink.tab(.inventory).url)
    }
}

private struct LowStockRow: View {
    let item: TodaySummarySnapshot.LowStockItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(item.quantityFormatted)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(item.detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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

struct TodaySummaryWidget: Widget {
    let kind: String = TodaySummaryStore.todaySummaryWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodaySummaryProvider()) { entry in
            TodaySummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Today Summary")
        .description("Budget, inventory, and quick habit access.")
    }
}

struct LowStockWidget: Widget {
    let kind: String = TodaySummaryStore.lowStockWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LowStockWidgetProvider()) { entry in
            LowStockWidgetView(entry: entry)
        }
        .configurationDisplayName("Low Stock")
        .description("See items that need restocking.")
    }
}

#Preview("Today Summary", as: .systemMedium) {
    TodaySummaryWidget()
} timeline: {
    TodaySummaryEntry(date: .now, summary: .placeholder)
}

#Preview("Low Stock", as: .systemMedium) {
    LowStockWidget()
} timeline: {
    LowStockWidgetEntry(date: .now, items: TodaySummarySnapshot.placeholder.lowStockItems)
}
