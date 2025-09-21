import Combine
import SwiftData
import SwiftUI

struct HabitsView: View {
    @Environment(\.services) private var services
    @StateObject private var viewModel = HabitsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.habits.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading habits…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding()
                } else if viewModel.habits.isEmpty {
                    ContentUnavailableView(
                        "No habits yet",
                        systemImage: "sparkles",
                        description: Text("Use the add button to start building routines.")
                    )
                    .padding(.top, 48)
                } else {
                    List {
                        if let analytics = viewModel.analytics {
                            Section("Analytics") {
                                HabitAnalyticsView(state: analytics)
                            }
                        }

                        if let timer = viewModel.activeTimer {
                            Section("Focus Session") {
                                HabitTimerView(
                                    timer: timer,
                                    stop: { viewModel.stopTimer(triggerCompletion: false) }
                                )
                            }
                        }

                        Section("Habits") {
                            ForEach(viewModel.habits) { habit in
                                HabitRow(
                                    habit: habit,
                                    isActiveTimer: viewModel.activeTimer?.habitId == habit.id,
                                    tick: { viewModel.tick(habit: habit) },
                                    startTimer: { viewModel.startTimer(for: habit) },
                                    stopTimer: { viewModel.stopTimer(triggerCompletion: false) },
                                    edit: { viewModel.editHabit(habit) }
                                )
                                .swipeActions(edge: .trailing) {
                                    Button("Edit") {
                                        viewModel.editHabit(habit)
                                    }
                                    .tint(.accentColor)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showAddHabit()
                    } label: {
                        Label("Add Habit", systemImage: "plus")
                    }
                }
            }
            .task {
                viewModel.configure(services: services)
                viewModel.refresh()
            }
            .alert("Habit Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .sheet(isPresented: $viewModel.isPresentingForm) {
                HabitEditorSheet(viewModel: viewModel)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }
}

// MARK: - Analytics

private struct HabitAnalyticsView: View {
    let state: HabitAnalyticsState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HabitAnalyticsMetric(
                title: "Adherence",
                value: state.adherenceDisplay,
                subtitle: state.adherenceDetail
            )

            Divider()

            HabitAnalyticsMetric(
                title: "Longest streak",
                value: state.longestStreakDisplay,
                subtitle: state.longestStreakDetail
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct HabitAnalyticsMetric: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Habit Row

private struct HabitRow: View {
    let habit: HabitRowState
    let isActiveTimer: Bool
    let tick: () -> Void
    let startTimer: () -> Void
    let stopTimer: () -> Void
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(habit.scheduleRule)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(habit.streakDisplay)
                    .font(.caption.monospacedDigit())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(habit.streakBackgroundColor)
                    )
                    .foregroundStyle(habit.streakForegroundColor)
                    .accessibilityLabel(habit.streakAccessibilityLabel)
            }

            HStack(spacing: 12) {
                Label(habit.targetDescription, systemImage: habit.unit.iconName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                switch habit.unit {
                case .duration:
                    if isActiveTimer {
                        Button(action: stopTimer) {
                            Label("Stop", systemImage: "stop.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Stop focus timer")
                    } else {
                        Button(action: startTimer) {
                            Label("Focus", systemImage: "play.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.accentColor)
                        .accessibilityLabel("Start focus timer")
                    }
                case .boolean, .count:
                    Button(action: tick) {
                        Label("Tick", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.accentColor)
                    .accessibilityLabel("Complete habit")
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
    }
}

// MARK: - Timer View

private struct HabitTimerView: View {
    let timer: HabitTimerState
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timer.habitName)
                        .font(.headline)
                    Text("Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: stop) {
                    Label("Stop", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            ProgressView(value: timer.progress)
                .tint(.accentColor)

            HStack {
                Label(timer.elapsedDisplay, systemImage: "hourglass.bottomhalf.fill")
                Spacer()
                Label(timer.remainingDisplay, systemImage: "hourglass.tophalf.fill")
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - View Model

@MainActor
final class HabitsViewModel: ObservableObject {
    @Published private(set) var habits: [HabitRowState] = []
    @Published private(set) var analytics: HabitAnalyticsState?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPresentingForm = false
    @Published var form = HabitForm()
    @Published private(set) var activeTimer: HabitTimerState?

    var canSaveHabit: Bool {
        form.isValid
    }

    private var services: ServiceContainer?
    private var eventSubscription: AnyCancellable?
    private var timerSubscription: AnyCancellable?
    private let timerActivityController = FocusActivityController()

    func configure(services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services
        subscribeToEvents(using: services)
    }

    deinit {
        eventSubscription?.cancel()
        timerSubscription?.cancel()
    }

    func refresh() {
        guard let services else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let models = try services.persistence.habits.fetch(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            habits = models.map(HabitRowState.init(habit:))
            analytics = HabitAnalyticsState(habits: habits)
        } catch {
            errorMessage = "Unable to load habits. \(error.localizedDescription)"
        }
    }

    func showAddHabit() {
        form = HabitForm()
        isPresentingForm = true
    }

    func editHabit(_ habit: HabitRowState) {
        form = HabitForm(habit: habit)
        isPresentingForm = true
    }

    func dismissForm() {
        isPresentingForm = false
    }

    func saveHabit() {
        guard canSaveHabit, let services else { return }
        do {
            if let id = form.id,
               let habit = try services.persistence.habits.first(where: #Predicate { $0.id == id }) {
                try services.persistence.habits.performAndSave {
                    habit.name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    habit.scheduleRule = form.scheduleRule.trimmingCharacters(in: .whitespacesAndNewlines)
                    habit.unit = form.unit.storageValue
                    habit.target = form.effectiveTarget
                }
            } else {
                _ = try services.persistence.habits.create {
                    try Habit(
                        name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        scheduleRule: form.scheduleRule.trimmingCharacters(in: .whitespacesAndNewlines),
                        unit: form.unit.storageValue,
                        target: form.effectiveTarget
                    )
                }
            }
            dismissForm()
            refresh()
        } catch {
            errorMessage = "Unable to save habit. \(error.localizedDescription)"
        }
    }

    func tick(habit: HabitRowState, amount: Double? = nil) {
        guard let services else { return }
        do {
            guard let model = try services.persistence.habits.first(where: #Predicate { $0.id == habit.id }) else {
                return
            }

            let increment = amount ?? habit.target
            var didComplete = false

            try services.persistence.habits.performAndSave {
                model.lastCheckIn = .now
                if increment >= model.target {
                    model.streak += 1
                    didComplete = true
                }
            }

            let updatedStreak = model.streak
            let payload: [String: Any] = [
                "habitId": habit.id.uuidString,
                "habitName": habit.name,
                "amount": increment,
                "streak": updatedStreak,
                "completed": didComplete
            ]

            try appendEvent(kind: .habitTicked, payload: payload, related: [habit.id])
            services.events.post(kind: .habitTicked, payload: payload)

            if didComplete {
                let completionPayload: [String: Any] = [
                    "habitId": habit.id.uuidString,
                    "habitName": habit.name,
                    "streak": updatedStreak
                ]
                try appendEvent(kind: .habitCompleted, payload: completionPayload, related: [habit.id])
                services.events.post(kind: .habitCompleted, payload: completionPayload)
            }

            if activeTimer?.habitId == habit.id {
                stopTimer(triggerCompletion: false)
            }

            refresh()
        } catch {
            errorMessage = "Unable to update habit. \(error.localizedDescription)"
        }
    }

    func startTimer(for habit: HabitRowState) {
        guard habit.unit == .duration else { return }
        guard let duration = habit.durationSeconds, duration > 0 else { return }

        if activeTimer != nil {
            stopTimer(triggerCompletion: false)
        }

        var state = HabitTimerState(
            habitId: habit.id,
            habitName: habit.name,
            duration: TimeInterval(duration),
            startedAt: .now
        )
        state.update(now: .now)
        activeTimer = state

        timerSubscription?.cancel()
        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                Task { @MainActor [weak self] in
                    self?.updateTimer(now: date)
                }
            }

        Task { await timerActivityController.start(timer: state) }
    }

    func stopTimer(triggerCompletion: Bool) {
        let currentTimer = activeTimer
        timerSubscription?.cancel()
        timerSubscription = nil
        activeTimer = nil

        Task { await timerActivityController.end() }

        if triggerCompletion, let timer = currentTimer,
           let habit = habits.first(where: { $0.id == timer.habitId }) {
            tick(habit: habit, amount: habit.target)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func binding<Value>(_ keyPath: WritableKeyPath<HabitForm, Value>) -> Binding<Value> {
        Binding(
            get: { self.form[keyPath: keyPath] },
            set: { self.form[keyPath: keyPath] = $0 }
        )
    }

    func unitBinding() -> Binding<HabitUnit> {
        Binding(
            get: { self.form.unit },
            set: { newValue in
                guard self.form.unit != newValue else { return }
                self.form.unit = newValue
                self.updateTarget(for: newValue)
            }
        )
    }

    private func updateTarget(for unit: HabitUnit) {
        switch unit {
        case .boolean:
            form.target = 1
        case .count:
            form.target = max(1, form.target.rounded())
        case .duration:
            form.target = max(25, form.target)
        }
    }

    private func subscribeToEvents(using services: ServiceContainer) {
        eventSubscription = services.events.subscribe { [weak self] event in
            guard let self else { return }
            switch event.kind {
            case .habitStarted, .habitTicked, .habitCompleted:
                Task { @MainActor in
                    self.refresh()
                }
            default:
                break
            }
        }
    }

    private func updateTimer(now date: Date) {
        guard var timer = activeTimer else { return }
        timer.update(now: date)
        activeTimer = timer

        if timer.remaining <= 0 {
            stopTimer(triggerCompletion: true)
        } else {
            Task { await timerActivityController.update(timer: timer) }
        }
    }

    private func appendEvent(kind: DomainEventKind, payload: [String: Any], related: [UUID]) throws {
        guard let services else { return }
        let json = try jsonString(from: payload)
        try services.persistence.eventStore.append(
            kind: kind.rawValue,
            payloadJSON: json,
            relatedIds: related
        )
    }

    private func jsonString(from payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Sheet

private struct HabitEditorSheet: View {
    @ObservedObject var viewModel: HabitsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: viewModel.binding(\.name))
                    TextField("Schedule rule", text: viewModel.binding(\.scheduleRule))

                    Picker("Unit", selection: viewModel.unitBinding()) {
                        ForEach(HabitUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                }

                Section("Target") {
                    switch viewModel.form.unit {
                    case .boolean:
                        Label("Complete once per schedule", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    case .count:
                        Stepper(value: viewModel.binding(\.target), in: 1...200, step: 1) {
                            let count = Int(viewModel.form.target)
                            Text(count == 1 ? "1 time" : "\(count) times")
                        }
                    case .duration:
                        Stepper(value: viewModel.binding(\.target), in: 5...480, step: 5) {
                            Text(viewModel.form.durationDisplay)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.form.id == nil ? "New Habit" : "Edit Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.dismissForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveHabit()
                    }
                    .disabled(!viewModel.canSaveHabit)
                }
            }
        }
    }
}

// MARK: - View State

private struct HabitRowState: Identifiable, Equatable {
    let id: UUID
    let name: String
    let scheduleRule: String
    let unit: HabitUnit
    let target: Double
    let streak: Int
    let lastCheckIn: Date?

    init(habit: Habit) {
        self.id = habit.id
        self.name = habit.name
        self.scheduleRule = habit.scheduleRule
        self.unit = HabitUnit(storedValue: habit.unit)
        self.target = habit.target
        self.streak = habit.streak
        self.lastCheckIn = habit.lastCheckIn
    }

    var targetDescription: String {
        switch unit {
        case .boolean:
            return "Complete once"
        case .count:
            let count = Int(target)
            if count == 1 {
                return "Target: 1 time"
            }
            return "Target: \(count) times"
        case .duration:
            return "Focus for \(durationDisplay)"
        }
    }

    var streakDisplay: String {
        "🔥 \(streak)"
    }

    var streakAccessibilityLabel: String {
        if streak == 1 {
            return "1 day streak"
        }
        return "\(streak) day streak"
    }

    var streakBackgroundColor: Color {
        streak > 0 ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12)
    }

    var streakForegroundColor: Color {
        streak > 0 ? .orange : .secondary
    }

    var durationSeconds: Int? {
        guard unit == .duration else { return nil }
        return max(1, Int(target * 60))
    }

    private var durationDisplay: String {
        guard unit == .duration else { return "" }
        let minutes = Int(target)
        return "\(minutes) min"
    }
}

private struct HabitAnalyticsState {
    let totalHabits: Int
    let completedToday: Int
    let longestStreak: Int

    init(habits: [HabitRowState]) {
        self.totalHabits = habits.count
        let today = Date()
        self.completedToday = habits.filter { habit in
            habit.lastCheckIn.map { Calendar.current.isDate($0, inSameDayAs: today) } ?? false
        }.count
        self.longestStreak = habits.map(\.streak).max() ?? 0
    }

    var adherence: Double {
        guard totalHabits > 0 else { return 0 }
        return Double(completedToday) / Double(totalHabits)
    }

    var adherenceDisplay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: adherence)) ?? "0%"
    }

    var adherenceDetail: String {
        if totalHabits == 0 { return "No habits" }
        return "\(completedToday) of \(totalHabits) today"
    }

    var longestStreakDisplay: String {
        longestStreak > 0 ? "\(longestStreak) days" : "0 days"
    }

    var longestStreakDetail: String {
        if longestStreak == 0 {
            return "Build your first streak"
        }
        return "Top habit streak"
    }
}

private struct HabitTimerState: Identifiable, Equatable {
    let id = UUID()
    let habitId: UUID
    let habitName: String
    let duration: TimeInterval
    let startedAt: Date
    private(set) var remaining: TimeInterval = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / duration))
    }

    var remainingDisplay: String {
        remaining.formattedDuration
    }

    var elapsedDisplay: String {
        max(0, duration - remaining).formattedDuration
    }

    mutating func update(now date: Date) {
        let elapsed = date.timeIntervalSince(startedAt)
        remaining = max(0, duration - elapsed)
    }

    var isComplete: Bool {
        remaining <= 0
    }
}

// MARK: - Form Model

private struct HabitForm: Equatable {
    var id: UUID?
    var name: String = ""
    var scheduleRule: String = ""
    var unit: HabitUnit = .boolean
    var target: Double = 1

    init() {}

    init(habit: HabitRowState) {
        self.id = habit.id
        self.name = habit.name
        self.scheduleRule = habit.scheduleRule
        self.unit = habit.unit
        switch habit.unit {
        case .boolean:
            self.target = 1
        case .count:
            self.target = habit.target
        case .duration:
            self.target = max(5, habit.target)
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !scheduleRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveTarget: Double {
        switch unit {
        case .boolean:
            return 1
        case .count:
            return max(1, target.rounded())
        case .duration:
            return max(5, target)
        }
    }

    var durationDisplay: String {
        let minutes = Int(target)
        if minutes == 1 {
            return "1 minute"
        }
        return "\(minutes) minutes"
    }
}

private enum HabitUnit: String, CaseIterable, Identifiable {
    case boolean = "bool"
    case count = "count"
    case duration = "duration"

    init(storedValue: String) {
        switch storedValue.lowercased() {
        case "bool", "boolean":
            self = .boolean
        case "duration", "time":
            self = .duration
        default:
            self = .count
        }
    }

    var id: String { rawValue }

    var storageValue: String { rawValue }

    var displayName: String {
        switch self {
        case .boolean:
            return "Yes/No"
        case .count:
            return "Count"
        case .duration:
            return "Duration"
        }
    }

    var iconName: String {
        switch self {
        case .boolean:
            return "checkmark.circle"
        case .count:
            return "number.square"
        case .duration:
            return "timer"
        }
    }
}

// MARK: - Focus Activity Controller

private protocol FocusActivityHandling {
    var isAvailable: Bool { get }
    func start(timer: HabitTimerState) async
    func update(timer: HabitTimerState) async
    func end() async
}

private final class FocusActivityController {
    private let handler: FocusActivityHandling

    init() {
        #if canImport(ActivityKit)
        if #available(iOS 17.0, *) {
            handler = LiveFocusActivityController()
        } else {
            handler = NoFocusActivityController()
        }
        #else
        handler = NoFocusActivityController()
        #endif
    }

    func start(timer: HabitTimerState) async {
        await handler.start(timer: timer)
    }

    func update(timer: HabitTimerState) async {
        await handler.update(timer: timer)
    }

    func end() async {
        await handler.end()
    }
}

private struct NoFocusActivityController: FocusActivityHandling {
    var isAvailable: Bool { false }
    func start(timer: HabitTimerState) async {}
    func update(timer: HabitTimerState) async {}
    func end() async {}
}

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 17.0, *)
private struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var habitName: String
        var remaining: Int
        var total: Int
    }

    var habitId: UUID
    var title: String
}

@available(iOS 17.0, *)
private final class LiveFocusActivityController: FocusActivityHandling {
    private var activity: Activity<FocusActivityAttributes>?

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(timer: HabitTimerState) async {
        guard isAvailable else { return }
        let attributes = FocusActivityAttributes(
            habitId: timer.habitId,
            title: timer.habitName
        )
        let content = FocusActivityAttributes.ContentState(
            habitName: timer.habitName,
            remaining: Int(timer.remaining),
            total: Int(timer.duration)
        )

        activity = try? Activity.request(attributes: attributes, contentState: content)
    }

    func update(timer: HabitTimerState) async {
        guard let activity else { return }
        let content = FocusActivityAttributes.ContentState(
            habitName: timer.habitName,
            remaining: Int(timer.remaining),
            total: Int(timer.duration)
        )
        await activity.update(using: content)
    }

    func end() async {
        guard let activity else { return }
        await activity.end(dismissalPolicy: .immediate)
        self.activity = nil
    }
}
#endif

// MARK: - Utilities

private extension TimeInterval {
    var formattedDuration: String {
        let seconds = max(0, Int(self))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        let formatter = NumberFormatter()
        formatter.minimumIntegerDigits = 2
        let secondsString = formatter.string(from: NSNumber(value: remainingSeconds)) ?? "00"
        return "\(minutes):\(secondsString)"
    }
}

#Preview {
    HabitsPreview.make()
}

private enum HabitsPreview {
    @MainActor
    static func make() -> some View {
        let services = ServiceContainer.makePreview()
        let repository = services.persistence.habits
        if let existing = try? repository.fetch() {
            for habit in existing {
                try? repository.delete(habit)
            }
        }
        _ = try? repository.create {
            try Habit(
                name: "Morning Meditation",
                scheduleRule: "Daily",
                unit: HabitUnit.duration.storageValue,
                target: 25,
                streak: 5,
                lastCheckIn: Calendar.current.date(byAdding: .day, value: -1, to: .now)
            )
        }
        _ = try? repository.create {
            try Habit(
                name: "Hydrate",
                scheduleRule: "Daily",
                unit: HabitUnit.count.storageValue,
                target: 8,
                streak: 12,
                lastCheckIn: .now
            )
        }
        _ = try? repository.create {
            try Habit(
                name: "Inbox Zero",
                scheduleRule: "Weekdays",
                unit: HabitUnit.boolean.storageValue,
                target: 1,
                streak: 3,
                lastCheckIn: .now
            )
        }

        return HabitsView()
            .environment(\.services, services)
    }
}
