import SwiftUI

struct TodayView: View {
    @Environment(\.services) private var services
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = TodayViewModel()

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    Button {
                        store.send(.selectTab(.expenses))
                    } label: {
                        BudgetCard(budget: viewModel.summary.budget)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.send(.selectTab(.inventory))
                    } label: {
                        LowStockCard(count: viewModel.summary.lowStockCount)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CalendarLinksView()
                    } label: {
                        CalendarCard(calendar: viewModel.summary.calendar)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.send(.selectTab(.habits))
                    } label: {
                        HabitsCard(habits: viewModel.summary.habits)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.send(.selectTab(.inbox))
                    } label: {
                        InboxCard(count: viewModel.summary.inboxCount)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .task {
                viewModel.configure(services: services)
                viewModel.refresh()
            }
            .refreshable {
                viewModel.refresh()
            }
            .overlay(alignment: .topTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
    }
}

private struct BudgetCard: View {
    let budget: TodaySummarySnapshot.Budget?

    var body: some View {
        TodayCard(title: "Budget left", systemIcon: "creditcard") {
            if let budget {
                VStack(alignment: .leading, spacing: 8) {
                    Text(budget.remainingFormatted)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    ProgressView(value: budget.progress)
                        .tint(.green)
                    Text("of \(budget.limitFormatted) this month")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Set up envelopes to track your spending")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LowStockCard: View {
    let count: Int

    var body: some View {
        TodayCard(title: "Low stock", systemIcon: "shippingbox", accentColor: .orange) {
            if count > 0 {
                Text("\(count) item\(count == 1 ? "" : "s") need restock")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            } else {
                Text("Everything is topped up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CalendarCard: View {
    let calendar: TodaySummarySnapshot.Calendar

    private var accentColor: Color {
        switch calendar.state {
        case .event:
            return .blue
        case .needsPermission:
            return .orange
        default:
            return .accentColor
        }
    }

    var body: some View {
        TodayCard(title: "Next calendar block", systemIcon: "calendar", accentColor: accentColor) {
            VStack(alignment: .leading, spacing: 6) {
                Text(calendar.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if let subtitle = calendar.displaySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let footnote = calendar.displayFootnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HabitsCard: View {
    let habits: [TodaySummarySnapshot.Habit]

    var body: some View {
        TodayCard(title: "Habits", systemIcon: "repeat", accentColor: .purple) {
            if habits.isEmpty {
                Text("Add habits to build your routines")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(habits) { habit in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(habit.schedule)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(habit.streakDisplay)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text(habit.statusDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct InboxCard: View {
    let count: Int

    var body: some View {
        TodayCard(title: "Inbox", systemIcon: "tray", accentColor: .teal) {
            if count == 0 {
                Text("Inbox zero — nice!")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(count) item\(count == 1 ? "" : "s") waiting")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct TodayCard<Content: View>: View {
    let title: String
    let systemIcon: String
    let accentColor: Color
    @ViewBuilder var content: Content

    init(title: String, systemIcon: String, accentColor: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemIcon = systemIcon
        self.accentColor = accentColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: systemIcon)
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(accentColor.opacity(0.12))
                    )

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

#Preview {
    let services = ServiceContainer.makePreview()
    let reducer = AppReducer(services: services, persistence: services.persistence, syncService: SyncService())
    return TodayView()
        .environment(\.services, services)
        .environmentObject(AppStore(initialState: AppState(), reducer: reducer))
}
