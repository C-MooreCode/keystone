import SwiftData
import SwiftUI

struct ShoppingView: View {
    @Environment(\.services) private var services
    @StateObject private var viewModel = ShoppingViewModel()

    private var listSelectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedListId },
            set: { viewModel.selectList(id: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.lists.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading shopping lists…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.lists.isEmpty {
                    ContentUnavailableView(
                        "No shopping lists",
                        systemImage: "cart",
                        description: Text("Add low stock items from Inventory or create a list for a store.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        if viewModel.lists.count > 1 {
                            Picker("Store", selection: listSelectionBinding) {
                                ForEach(viewModel.lists) { list in
                                    Text(list.displayName)
                                        .tag(list.id as UUID?)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                        }

                        if let summary = viewModel.selectedList {
                            ShoppingListSummaryView(summary: summary)
                                .padding(.horizontal)
                        }

                        List {
                            ForEach(viewModel.lineGroups) { group in
                                Section(group.title) {
                                    ForEach(group.lines) { line in
                                        ShoppingLineRow(
                                            line: line,
                                            markBought: { viewModel.beginMarkBought(line: line) },
                                            revert: { viewModel.markAsPending(lineId: line.id) }
                                        )
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            if line.isPending {
                                                Button("Bought") {
                                                    viewModel.beginMarkBought(line: line)
                                                }
                                                .tint(.green)
                                            } else {
                                                Button("Undo") {
                                                    viewModel.markAsPending(lineId: line.id)
                                                }
                                                .tint(.orange)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if viewModel.isLiveActivityAvailable,
                       let summary = viewModel.selectedList,
                       summary.pendingCount > 0 {
                        if viewModel.hasActiveStoreTrip {
                            Button("End Store Trip") {
                                viewModel.endStoreTrip()
                            }
                            .accessibilityIdentifier("shopping-end-trip")
                        } else {
                            Button("Start Store Trip") {
                                viewModel.startStoreTrip()
                            }
                            .accessibilityIdentifier("shopping-start-trip")
                        }
                    }
                }
            }
            .task {
                viewModel.configure(services: services)
                viewModel.refresh()
            }
            .onOpenURL { url in
                viewModel.handleDeepLink(url)
            }
            .alert("Shopping Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .sheet(item: $viewModel.activePricePrompt) { prompt in
                ShoppingPricePromptView(
                    prompt: prompt,
                    confirm: { value in viewModel.completePurchase(with: value) },
                    skip: { viewModel.skipPriceEntry() },
                    cancel: { viewModel.cancelPriceEntry() }
                )
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

private struct ShoppingListSummaryView: View {
    let summary: ShoppingListViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.displayName)
                    .font(.title3.weight(.semibold))
                Spacer()
                if summary.totalItems > 0 {
                    Text("\(summary.completedCount)/\(summary.totalItems) complete")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if summary.totalItems > 0 {
                ProgressView(value: summary.progress)
                    .tint(.green)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct ShoppingLineRow: View {
    let line: ShoppingLineViewState
    let markBought: () -> Void
    let revert: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                if line.isPending {
                    markBought()
                } else {
                    revert()
                }
            } label: {
                Image(systemName: line.isPending ? "circle" : "checkmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(line.isPending ? .secondary : .green)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(line.name)
                    .font(.body.weight(.semibold))
                if let subtitle = line.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(line.quantityDisplay)
                    .font(.body.monospacedDigit())
                if let price = line.lastPriceDisplay {
                    Text(price)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ShoppingPricePromptView: View {
    let prompt: ShoppingPricePromptState
    let confirm: (Decimal?) -> Void
    let skip: () -> Void
    let cancel: () -> Void

    @State private var priceText: String
    @Environment(\.dismiss) private var dismiss

    init(prompt: ShoppingPricePromptState, confirm: @escaping (Decimal?) -> Void, skip: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.prompt = prompt
        self.confirm = confirm
        self.skip = skip
        self.cancel = cancel
        _priceText = State(initialValue: prompt.suggestedPriceString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.lineName)
                            .font(.headline)
                        Text(prompt.quantityDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Price Paid") {
                    TextField("Enter price", text: $priceText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button("Skip Price") {
                        dismiss()
                        skip()
                    }
                    .tint(.secondary)
                }
            }
            .navigationTitle("Mark Bought")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        cancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Bought") {
                        dismiss()
                        confirm(parsedPrice)
                    }
                    .disabled(!isInputValid)
                }
            }
        }
    }

    private var isInputValid: Bool {
        priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedPrice != nil
    }

    private var parsedPrice: Decimal? {
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sanitized = trimmed
            .replacingOccurrences(of: Locale.current.currencySymbol ?? "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: sanitized)
    }
}

@MainActor
final class ShoppingViewModel: ObservableObject {
    @Published var lists: [ShoppingListViewState] = []
    @Published var selectedListId: UUID? {
        didSet {
            guard selectedListId != oldValue else { return }
            persistSelectedList(id: selectedListId)
            Task { await syncLiveActivity() }
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var activePricePrompt: ShoppingPricePromptState?
    @Published var hasActiveStoreTrip = false
    @Published var isLiveActivityAvailable = false

    var selectedList: ShoppingListViewState? {
        guard let selectedListId else { return nil }
        return lists.first(where: { $0.id == selectedListId })
    }

    var lineGroups: [ShoppingLineGroup] {
        selectedList?.lineGroups ?? []
    }

    private var services: ServiceContainer?
    private var pendingSelection: UUID?
    private var pendingDeepLinkSelection: UUID?
    private let defaultsKey = "shopping.selectedListId"
    private let activityController = StoreTripActivityController()

    func configure(services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services
        pendingSelection = loadPersistedListId()
        Task { await syncLiveActivity() }
    }

    func refresh() {
        guard let services else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let inventoryItems = try services.persistence.inventoryItems.fetch()
            var inventoryLookup: [UUID: InventoryItem] = [:]
            for item in inventoryItems {
                inventoryLookup[item.id] = item
            }

            let lists = try services.persistence.shoppingLists.fetch(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )

            let listStates: [ShoppingListViewState] = lists.map { list in
                let lineStates = list.lines.map { line -> ShoppingLineViewState in
                    let inventory = line.inventoryItemId.flatMap { inventoryLookup[$0] }
                    return ShoppingLineViewState(
                        id: line.id,
                        name: line.name,
                        status: ShoppingLineStatus(rawValue: line.status),
                        desiredQty: line.desiredQty,
                        inventoryItemId: line.inventoryItemId,
                        unit: inventory?.unit,
                        lastPricePaid: inventory?.lastPricePaid,
                        preferredMerchantId: line.preferredMerchantId
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.isPending == rhs.isPending {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.isPending && !rhs.isPending
                }

                return ShoppingListViewState(
                    id: list.id,
                    name: list.name,
                    lines: lineStates
                )
            }

            listsUpdated(listStates)
        } catch {
            errorMessage = "Unable to load shopping lists. \(error.localizedDescription)"
        }
    }

    func selectList(id: UUID?) {
        selectedListId = id
    }

    func beginMarkBought(line: ShoppingLineViewState) {
        if let itemId = line.inventoryItemId {
            activePricePrompt = ShoppingPricePromptState(
                lineId: line.id,
                lineName: line.name,
                quantity: line.desiredQty,
                unit: line.unit,
                suggestedPrice: line.lastPricePaid,
                inventoryItemId: itemId
            )
        } else {
            finalizePurchase(lineId: line.id, price: nil)
        }
    }

    func markAsPending(lineId: UUID) {
        guard let services else { return }
        do {
            if let line = try services.persistence.shoppingListLines.first(where: #Predicate { $0.id == lineId }) {
                try services.persistence.shoppingListLines.performAndSave {
                    line.status = ShoppingLineStatus.pending.rawValue
                }
                refresh()
            }
        } catch {
            errorMessage = "Unable to update item. \(error.localizedDescription)"
        }
    }

    func completePurchase(with value: Decimal?) {
        guard let prompt = activePricePrompt else { return }
        finalizePurchase(lineId: prompt.lineId, price: value)
    }

    func skipPriceEntry() {
        guard let prompt = activePricePrompt else { return }
        finalizePurchase(lineId: prompt.lineId, price: nil)
    }

    func cancelPriceEntry() {
        activePricePrompt = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func startStoreTrip() {
        guard let list = selectedList, activityController.isAvailable else { return }
        Task {
            await activityController.start(list: list)
            await syncLiveActivity()
        }
    }

    func endStoreTrip() {
        Task {
            await activityController.end()
            await syncLiveActivity()
        }
    }

    func handleDeepLink(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let components = url.pathComponents.filter { $0 != "/" }

        var targetId: UUID?
        if scheme == "shopping" {
            if components.count >= 2, components[0].lowercased() == "list" {
                targetId = UUID(uuidString: components[1])
            }
        } else if scheme == "keystone", host == "shopping" {
            if components.count >= 2, components[0].lowercased() == "list" {
                targetId = UUID(uuidString: components[1])
            }
        } else if host == "shopping" {
            if components.count >= 2, components[0].lowercased() == "list" {
                targetId = UUID(uuidString: components[1])
            }
        }

        guard let listId = targetId else { return }
        if lists.contains(where: { $0.id == listId }) {
            selectedListId = listId
        } else {
            pendingDeepLinkSelection = listId
        }
    }

    private func listsUpdated(_ newLists: [ShoppingListViewState]) {
        lists = newLists
        let availableIds = Set(newLists.map(\.id))

        if newLists.isEmpty {
            selectedListId = nil
            pendingSelection = nil
            return
        }

        if let deepLink = pendingDeepLinkSelection, availableIds.contains(deepLink) {
            pendingDeepLinkSelection = nil
            pendingSelection = nil
            if selectedListId != deepLink {
                selectedListId = deepLink
            } else {
                Task { await syncLiveActivity() }
            }
            return
        }

        if let persisted = pendingSelection, availableIds.contains(persisted) {
            pendingSelection = nil
            if selectedListId != persisted {
                selectedListId = persisted
            } else {
                Task { await syncLiveActivity() }
            }
            return
        }

        if let current = selectedListId, availableIds.contains(current) {
            Task { await syncLiveActivity() }
            return
        }

        selectedListId = newLists.first?.id
    }

    private func finalizePurchase(lineId: UUID, price: Decimal?) {
        guard let services else { return }
        do {
            guard let line = try services.persistence.shoppingListLines.first(where: #Predicate { $0.id == lineId }) else {
                activePricePrompt = nil
                refresh()
                return
            }

            let quantity = line.desiredQty
            let inventoryItemId = line.inventoryItemId

            try services.persistence.shoppingListLines.performAndSave {
                line.status = ShoppingLineStatus.purchased.rawValue
            }

            if let inventoryItemId,
               let item = try services.persistence.inventoryItems.first(where: #Predicate { $0.id == inventoryItemId }) {
                try services.persistence.inventoryItems.performAndSave {
                    item.qty = max(0, item.qty + quantity)
                    if let price, price > 0 {
                        item.lastPricePaid = price
                    }
                }
            }

            activePricePrompt = nil
            refresh()
        } catch {
            errorMessage = "Unable to mark item as bought. \(error.localizedDescription)"
        }
    }

    private func syncLiveActivity() async {
        if let list = selectedList {
            await activityController.update(list: list)
        } else {
            await activityController.end()
        }
        hasActiveStoreTrip = activityController.isActive
        isLiveActivityAvailable = activityController.isAvailable
    }

    private func loadPersistedListId() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        return UUID(uuidString: raw)
    }

    private func persistSelectedList(id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}

private struct ShoppingListViewState: Identifiable, Equatable {
    let id: UUID
    let name: String
    let lines: [ShoppingLineViewState]

    var displayName: String { name }

    var storeName: String {
        guard let range = name.range(of: " - ") else { return name }
        let trimmed = name[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : String(trimmed)
    }

    var pendingLines: [ShoppingLineViewState] { lines.filter(\.isPending) }
    var purchasedLines: [ShoppingLineViewState] { lines.filter { !$0.isPending } }

    var pendingCount: Int { pendingLines.count }
    var completedCount: Int { purchasedLines.count }
    var totalItems: Int { lines.count }

    var progress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedCount) / Double(totalItems)
    }

    var lineGroups: [ShoppingLineGroup] {
        var groups: [ShoppingLineGroup] = []
        if !pendingLines.isEmpty {
            groups.append(ShoppingLineGroup(id: "pending", title: "Pending", lines: pendingLines))
        }
        if !purchasedLines.isEmpty {
            groups.append(ShoppingLineGroup(id: "purchased", title: "Purchased", lines: purchasedLines))
        }
        return groups
    }
}

private struct ShoppingLineViewState: Identifiable, Equatable {
    let id: UUID
    let name: String
    let status: ShoppingLineStatus
    let desiredQty: Double
    let inventoryItemId: UUID?
    let unit: String?
    let lastPricePaid: Decimal?
    let preferredMerchantId: UUID?

    var isPending: Bool { status == .pending }

    var quantityDisplay: String {
        desiredQty.formattedQuantity(unit: unit)
    }

    var lastPriceDisplay: String? {
        lastPricePaid?.currencyFormatted.map { "Last paid \($0)" }
    }

    var subtitle: String? {
        isPending ? nil : "Marked bought"
    }
}

private struct ShoppingLineGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let lines: [ShoppingLineViewState]
}

private struct ShoppingPricePromptState: Identifiable, Equatable {
    let id = UUID()
    let lineId: UUID
    let lineName: String
    let quantity: Double
    let unit: String?
    let suggestedPrice: Decimal?
    let inventoryItemId: UUID

    var quantityDisplay: String {
        quantity.formattedQuantity(unit: unit)
    }

    var suggestedPriceString: String {
        guard let suggestedPrice else { return "" }
        return (suggestedPrice as NSDecimalNumber).stringValue
    }
}

private enum ShoppingLineStatus: String {
    case pending
    case purchased

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "purchased":
            self = .purchased
        default:
            self = .pending
        }
    }
}

private extension Decimal {
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}

private extension Double {
    func formattedQuantity(unit: String?) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        let value = formatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
        if let unit, !unit.isEmpty {
            return "\(value) \(unit)"
        }
        return value
    }
}

private protocol StoreTripActivityHandling {
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    func start(list: ShoppingListViewState) async
    func update(list: ShoppingListViewState?) async
    func end() async
}

private final class StoreTripActivityController {
    private let handler: StoreTripActivityHandling

    init() {
        #if canImport(ActivityKit)
        if #available(iOS 17.0, *) {
            handler = LiveStoreTripActivityController()
        } else {
            handler = NoActivityController()
        }
        #else
        handler = NoActivityController()
        #endif
    }

    var isAvailable: Bool { handler.isAvailable }
    var isActive: Bool { handler.isActive }

    func start(list: ShoppingListViewState) async {
        await handler.start(list: list)
    }

    func update(list: ShoppingListViewState?) async {
        await handler.update(list: list)
    }

    func end() async {
        await handler.end()
    }
}

private struct NoActivityController: StoreTripActivityHandling {
    var isAvailable: Bool { false }
    var isActive: Bool { false }
    func start(list: ShoppingListViewState) async {}
    func update(list: ShoppingListViewState?) async {}
    func end() async {}
}

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 17.0, *)
private struct StoreTripActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var totalItems: Int
        var completedItems: Int
        var pendingItems: Int
    }

    var listId: UUID
    var storeName: String
    var title: String
}

@available(iOS 17.0, *)
private final class LiveStoreTripActivityController: StoreTripActivityHandling {
    private var activity: Activity<StoreTripActivityAttributes>?
    private var lastState: StoreTripActivityAttributes.ContentState?

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isActive: Bool {
        activity != nil
    }

    func start(list: ShoppingListViewState) async {
        guard isAvailable else { return }
        await end()

        let attributes = StoreTripActivityAttributes(
            listId: list.id,
            storeName: list.storeName,
            title: list.displayName
        )
        let state = StoreTripActivityAttributes.ContentState(
            totalItems: list.totalItems,
            completedItems: list.completedCount,
            pendingItems: list.pendingCount
        )

        do {
            activity = try Activity.request(attributes: attributes, contentState: state)
            lastState = state
        } catch {
            activity = nil
            lastState = nil
        }
    }

    func update(list: ShoppingListViewState?) async {
        guard let activity, let list else { return }
        let state = StoreTripActivityAttributes.ContentState(
            totalItems: list.totalItems,
            completedItems: list.completedCount,
            pendingItems: list.pendingCount
        )
        do {
            try await activity.update(using: state)
            lastState = state
        } catch {
            // Ignore failures to update live activity.
        }
    }

    func end() async {
        guard let activity else { return }
        let finalState = lastState ?? StoreTripActivityAttributes.ContentState(totalItems: 0, completedItems: 0, pendingItems: 0)
        do {
            try await activity.end(using: finalState, dismissalPolicy: .immediate)
        } catch {
            // Ignore failures when ending the live activity.
        }
        self.activity = nil
        lastState = nil
    }
}
#endif

#Preview {
    ShoppingView()
        .environment(\.services, ServiceContainer.makePreview())
}
