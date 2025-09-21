import SwiftData
import SwiftUI

struct InventoryView: View {
    @Environment(\.services) private var services
    @StateObject private var viewModel = InventoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.locations.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading inventory…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(viewModel.filteredLocations) { location in
                                InventoryLocationCard(
                                    location: location,
                                    selectItem: { item in viewModel.select(item: item) }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Inventory")
            .searchable(
                text: $viewModel.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search inventory")
            )
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            viewModel.mergeLowStockIntoShopping(preferredMerchantTag: nil)
                        } label: {
                            Label("Add All Low Stock", systemImage: "cart.badge.plus")
                        }
                        if !viewModel.merchantTags.isEmpty {
                            Section("Preferred merchant") {
                                ForEach(viewModel.merchantTags, id: \.self) { tag in
                                    Button {
                                        viewModel.mergeLowStockIntoShopping(preferredMerchantTag: tag)
                                    } label: {
                                        Label(
                                            "Add \(viewModel.displayName(forMerchantTag: tag))",
                                            systemImage: "cart"
                                        )
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Low stock", systemImage: "exclamationmark.triangle")
                            .badge(viewModel.lowStockCount)
                    }
                    .disabled(viewModel.lowStockCount == 0)

                    Button {
                        viewModel.showAddItem()
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                    .accessibilityIdentifier("inventory-add-item")
                }
            }
            .task {
                viewModel.configure(services: services)
                viewModel.refresh()
            }
            .alert("Inventory Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .alert("Inventory Updated", isPresented: successBinding) {
                Button("OK", role: .cancel) {
                    viewModel.clearSuccess()
                }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
            .sheet(isPresented: $viewModel.isPresentingAddSheet) {
                InventoryAddItemView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isPresentingScanner) {
                InventoryScannerSheet(controller: viewModel.scannerController) {
                    viewModel.dismissScanner()
                }
            }
            .sheet(item: $viewModel.selectedItem) { item in
                InventoryItemDetailView(item: item, context: viewModel)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    private var successBinding: Binding<Bool> {
        Binding(
            get: { viewModel.successMessage != nil },
            set: { if !$0 { viewModel.clearSuccess() } }
        )
    }
}

// MARK: - Location Card

private struct InventoryLocationCard: View {
    let location: InventoryLocationViewState
    let selectItem: (InventoryItemViewState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(location.name)
                    .font(.headline)
                Spacer()
                if location.lowStockCount > 0 {
                    Label("\(location.lowStockCount)", systemImage: "exclamationmark.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .help("Low stock items")
                }
            }

            if location.items.isEmpty {
                ContentUnavailableView(
                    "No items",
                    systemImage: "shippingbox",
                    description: Text("Use the add button to capture inventory.")
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(location.items) { item in
                        Button {
                            selectItem(item)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.tags.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.quantityDisplay)
                                        .font(.body.monospacedDigit())
                                    if let expiry = item.expiry {
                                        Text(expiry, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(item.isLowStock ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - Add Item Sheet

private struct InventoryAddItemView: View {
    @ObservedObject var viewModel: InventoryViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture mode") {
                    Picker("Mode", selection: $viewModel.addForm.mode) {
                        ForEach(InventoryAddMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    if viewModel.addForm.mode == .barcode {
                        TextField("Barcode", text: $viewModel.addForm.barcode)
                            .keyboardType(.numberPad)
                        Button("Scan barcode") {
                            viewModel.presentScanner()
                        }
                    }

                    TextField("Name", text: $viewModel.addForm.name)
                    TextField("Unit", text: $viewModel.addForm.unit)
                    Stepper(value: $viewModel.addForm.quantity, in: 0...999, step: 1) {
                        Text("Quantity: \(viewModel.addForm.quantity, specifier: "%.0f")")
                    }
                    Stepper(value: $viewModel.addForm.restockThreshold, in: 0...999, step: 1) {
                        Text("Restock threshold: \(viewModel.addForm.restockThreshold, specifier: "%.0f")")
                    }
                    Toggle("Has expiry date", isOn: $viewModel.addForm.hasExpiry.animation())
                    if viewModel.addForm.hasExpiry {
                        DatePicker(
                            "Expiry",
                            selection: Binding(
                                get: { viewModel.addForm.expiry ?? .now },
                                set: { viewModel.addForm.expiry = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                    }
                    TextField("Tags (comma separated)", text: $viewModel.addForm.tags)
                    TextField("Last price paid", text: $viewModel.addForm.lastPricePaid)
                        .keyboardType(.decimalPad)
                }

                Section("Location") {
                    Picker("Bin", selection: $viewModel.addForm.locationId) {
                        ForEach(viewModel.locationOptions) { option in
                            Text(option.name).tag(option.id as UUID?)
                        }
                    }
                }
            }
            .navigationTitle("Add Inventory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.dismissAddSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.submitAddItem()
                    }
                    .disabled(!viewModel.canSubmitNewItem)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: viewModel.addForm.hasExpiry) { hasExpiry in
            if hasExpiry && viewModel.addForm.expiry == nil {
                viewModel.addForm.expiry = .now
            }
            if !hasExpiry {
                viewModel.addForm.expiry = nil
            }
        }
    }
}

// MARK: - Item Detail

private struct InventoryItemDetailView: View {
    let item: InventoryItemViewState
    @ObservedObject var context: InventoryViewModel
    @State private var workingItem: InventoryItemViewState
    @State private var hasExpiry: Bool
    @State private var priceText: String

    init(item: InventoryItemViewState, context: InventoryViewModel) {
        self.item = item
        self.context = context
        _workingItem = State(initialValue: item)
        _hasExpiry = State(initialValue: item.expiry != nil)
        if let price = item.lastPricePaid {
            _priceText = State(initialValue: price.currencyFormatted)
        } else {
            _priceText = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quantity") {
                    Stepper {
                        Text(workingItem.quantityDisplay)
                    } onIncrement: {
                        workingItem.qty += 1
                        context.adjustQuantity(for: workingItem.id, delta: 1)
                    } onDecrement: {
                        guard workingItem.qty > 0 else { return }
                        workingItem.qty -= 1
                        context.adjustQuantity(for: workingItem.id, delta: -1)
                    }
                }

                Section("Restock") {
                    Stepper(value: $workingItem.restockThreshold, in: 0...999, step: 1) {
                        Text("Threshold: \(workingItem.restockThreshold, specifier: "%.0f")")
                    }
                    .onChange(of: workingItem.restockThreshold) { value in
                        context.updateThreshold(for: workingItem.id, threshold: value)
                    }
                }

                Section("Expiry") {
                    Toggle("Has expiry date", isOn: $hasExpiry.animation())
                        .onChange(of: hasExpiry) { value in
                            if value {
                                let newDate = workingItem.expiry ?? .now
                                workingItem.expiry = newDate
                                context.updateExpiry(for: workingItem.id, expiry: newDate)
                            } else {
                                workingItem.expiry = nil
                                context.updateExpiry(for: workingItem.id, expiry: nil)
                            }
                        }
                    if hasExpiry {
                        DatePicker(
                            "Expiry date",
                            selection: Binding(
                                get: { workingItem.expiry ?? .now },
                                set: { newValue in
                                    workingItem.expiry = newValue
                                    context.updateExpiry(for: workingItem.id, expiry: newValue)
                                }
                            ),
                            displayedComponents: [.date]
                        )
                    } else {
                        Button("Clear expiry") {
                            workingItem.expiry = nil
                            context.updateExpiry(for: workingItem.id, expiry: nil)
                        }
                        .disabled(workingItem.expiry == nil)
                    }
                }

                Section("Pricing") {
                    HStack {
                        Text("Last price paid")
                        Spacer()
                        if let price = workingItem.lastPricePaid {
                            Text(price.currencyFormatted)
                                .font(.body.monospacedDigit())
                        } else {
                            Text("Not recorded")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Update price", text: $priceText)
                        .keyboardType(.decimalPad)
                        .onSubmit { savePrice() }
                    Button("Save price") {
                        savePrice()
                    }
                }
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        context.dismissSelection()
                    }
                }
            }
        }
        .onChange(of: item) { newValue in
            workingItem = newValue
            hasExpiry = newValue.expiry != nil
            priceText = newValue.lastPricePaid?.currencyFormatted ?? ""
        }
    }

    private func savePrice() {
        let sanitized = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty {
            workingItem.lastPricePaid = nil
            context.updateLastPrice(for: workingItem.id, value: nil)
            return
        }
        if let decimal = Decimal(string: sanitized.replacingOccurrences(of: "$", with: "")) {
            workingItem.lastPricePaid = decimal
            priceText = decimal.currencyFormatted
            context.updateLastPrice(for: workingItem.id, value: decimal)
        }
    }
}

// MARK: - Scanner Sheet

private struct InventoryScannerSheet: View {
    let controller: PlatformViewController?
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let controller {
                    BarcodeScannerContainer(controller: controller)
                        .ignoresSafeArea()
                } else {
                    ProgressView("Preparing scanner…")
                        .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#if canImport(UIKit)
private typealias PlatformViewController = UIViewController
private struct BarcodeScannerContainer: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#elseif canImport(AppKit)
private typealias PlatformViewController = NSViewController
private struct BarcodeScannerContainer: NSViewControllerRepresentable {
    let controller: NSViewController

    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
#endif

// MARK: - View Model

@MainActor
final class InventoryViewModel: NSObject, ObservableObject {
    @Published var locations: [InventoryLocationViewState] = []
    @Published var searchQuery: String = ""
    @Published var selectedItem: InventoryItemViewState?
    @Published var isLoading = false
    @Published var isPresentingAddSheet = false
    @Published var isPresentingScanner = false
    @Published var addForm = InventoryAddItemForm()
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var lowStockCount: Int = 0
    @Published var merchantTags: [String] = []

    var locationOptions: [InventoryLocationOption] = []
    var canSubmitNewItem: Bool {
        !addForm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !addForm.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var scannerController: PlatformViewController? {
        scannerReference
    }

    var filteredLocations: [InventoryLocationViewState] {
        guard let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmpty else {
            return locations
        }
        return locations.map { location in
            let filteredItems = location.items.filter { item in
                item.name.lowercased().contains(trimmed)
                || item.tags.joined(separator: " ").lowercased().contains(trimmed)
                || (item.barcode?.lowercased().contains(trimmed) ?? false)
            }
            return InventoryLocationViewState(
                id: location.id,
                name: location.name,
                items: filteredItems,
                lowStockCount: filteredItems.filter(\.isLowStock).count
            )
        }
        .filter { !$0.items.isEmpty }
    }

    private var services: ServiceContainer?
    private var tracker = InventoryOperationTracker()
    private var scannerReference: PlatformViewController?

    func configure(services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services
    }

    func refresh() {
        guard let services else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let bins = try services.persistence.locationBins.fetch()
            var locationLookup: [UUID: String] = [:]
            bins.forEach { locationLookup[$0.id] = $0.name }

            let items = try services.persistence.inventoryItems.fetch(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )

            var grouped: [UUID?: [InventoryItemViewState]] = [:]
            var merchantSet = Set<String>()
            for item in items {
                let locationId = item.locationId
                let locationName: String
                if let locationId, let known = locationLookup[locationId] {
                    locationName = known
                } else if let locationId {
                    locationName = "Bin \(locationId.uuidString.prefix(4))"
                } else {
                    locationName = "Unassigned"
                }
                let threshold = item.restockThreshold.doubleValue
                let isLow = threshold > 0 && item.qty <= threshold
                let state = InventoryItemViewState(
                    id: item.id,
                    name: item.name,
                    qty: item.qty,
                    unit: item.unit,
                    locationId: locationId,
                    locationName: locationName,
                    expiry: item.expiry,
                    restockThreshold: threshold,
                    lastPricePaid: item.lastPricePaid,
                    tags: item.tags,
                    barcode: item.barcode,
                    isLowStock: isLow
                )
                grouped[locationId, default: []].append(state)
                item.tags.filter { $0.starts(with: "merchant:") }.forEach { merchantSet.insert($0) }
            }

            locations = grouped.map { key, items in
                let name = key.flatMap { locationLookup[$0] } ?? "Unassigned"
                return InventoryLocationViewState(
                    id: key,
                    name: name,
                    items: items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                    lowStockCount: items.filter(\.isLowStock).count
                )
            }
            .sorted { lhs, rhs in
                if lhs.name == "Unassigned" { return false }
                if rhs.name == "Unassigned" { return true }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            lowStockCount = items.filter { item in
                let threshold = item.restockThreshold.doubleValue
                return threshold > 0 && item.qty <= threshold
            }.count

            locationOptions = [.init(id: nil, name: "Unassigned")] + bins.map { InventoryLocationOption(id: $0.id, name: $0.name) }
            merchantTags = merchantSet.sorted { displayName(forMerchantTag: $0) < displayName(forMerchantTag: $1) }
            if let current = selectedItem,
               let updated = locations.flatMap(\.items).first(where: { $0.id == current.id }) {
                selectedItem = updated
            }
        } catch {
            errorMessage = "Unable to load inventory. \(error.localizedDescription)"
        }
    }

    func select(item: InventoryItemViewState) {
        selectedItem = item
    }

    func dismissSelection() {
        selectedItem = nil
    }

    func showAddItem() {
        addForm = InventoryAddItemForm()
        isPresentingAddSheet = true
    }

    func dismissAddSheet() {
        isPresentingAddSheet = false
        addForm = InventoryAddItemForm()
    }

    func presentScanner() {
        guard let services, !isPresentingScanner else { return }
        scannerReference = services.barcode.makeScanner(delegate: self)
        isPresentingScanner = true
    }

    func dismissScanner() {
        isPresentingScanner = false
        scannerReference = nil
    }

    func submitAddItem() {
        guard let services else { return }
        do {
            let locationId = addForm.locationId
            let tags = addForm.tagArray
            let threshold = Decimal(addForm.restockThreshold)
            let lastPrice = addForm.lastPriceDecimal
            _ = try services.persistence.inventoryItems.create {
                try InventoryItem(
                    name: addForm.name,
                    barcode: addForm.barcode.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                    qty: addForm.quantity,
                    unit: addForm.unit,
                    locationId: locationId,
                    expiry: addForm.resolvedExpiry,
                    restockThreshold: threshold,
                    tags: tags,
                    lastPricePaid: lastPrice
                )
            }
            successMessage = "Added \(addForm.name)."
            dismissAddSheet()
            refresh()
        } catch {
            errorMessage = "Unable to add item. \(error.localizedDescription)"
        }
    }

    func adjustQuantity(for itemId: UUID, delta: Double, operationId: UUID = UUID()) {
        guard let services else { return }
        guard tracker.markAdjustment(id: operationId) else { return }
        do {
            if let item = try services.persistence.inventoryItems.first(where: #Predicate { $0.id == itemId }) {
                try services.persistence.inventoryItems.performAndSave {
                    let updated = max(0, item.qty + delta)
                    item.qty = updated
                }
                refresh()
            }
        } catch {
            errorMessage = "Unable to adjust quantity. \(error.localizedDescription)"
        }
    }

    func updateThreshold(for itemId: UUID, threshold: Double) {
        guard let services else { return }
        do {
            if let item = try services.persistence.inventoryItems.first(where: #Predicate { $0.id == itemId }) {
                try services.persistence.inventoryItems.performAndSave {
                    item.restockThreshold = Decimal(threshold)
                }
                refresh()
            }
        } catch {
            errorMessage = "Unable to update threshold. \(error.localizedDescription)"
        }
    }

    func updateExpiry(for itemId: UUID, expiry: Date?) {
        guard let services else { return }
        do {
            if let item = try services.persistence.inventoryItems.first(where: #Predicate { $0.id == itemId }) {
                try services.persistence.inventoryItems.performAndSave {
                    item.expiry = expiry
                }
                refresh()
            }
        } catch {
            errorMessage = "Unable to update expiry. \(error.localizedDescription)"
        }
    }

    func updateLastPrice(for itemId: UUID, value: Decimal?) {
        guard let services else { return }
        do {
            if let item = try services.persistence.inventoryItems.first(where: #Predicate { $0.id == itemId }) {
                try services.persistence.inventoryItems.performAndSave {
                    item.lastPricePaid = value
                }
                refresh()
            }
        } catch {
            errorMessage = "Unable to update price. \(error.localizedDescription)"
        }
    }

    func mergeLowStockIntoShopping(preferredMerchantTag: String?, operationId: UUID = UUID()) {
        guard let services else { return }
        guard tracker.markMerge(id: operationId) else { return }
        do {
            let items = try services.persistence.inventoryItems.fetch()
            let lowItems = items.filter { item in
                let threshold = item.restockThreshold.doubleValue
                guard threshold > 0, item.qty <= threshold else { return false }
                if let preferredMerchantTag {
                    return item.tags.contains(where: { $0.caseInsensitiveCompare(preferredMerchantTag) == .orderedSame })
                }
                return true
            }
            guard !lowItems.isEmpty else { return }

            let listName: String
            if let preferredMerchantTag {
                listName = "Shopping - \(displayName(forMerchantTag: preferredMerchantTag))"
            } else {
                listName = "Shopping"
            }

            let list: ShoppingList
            if let existing = try services.persistence.shoppingLists.first(where: #Predicate { $0.name == listName }) {
                list = existing
            } else {
                list = try services.persistence.shoppingLists.create {
                    try ShoppingList(name: listName)
                }
            }

            for item in lowItems {
                let missingQty = max(item.restockThreshold.doubleValue - item.qty, 1)
                if let existingLine = list.lines.first(where: { $0.inventoryItemId == item.id && $0.status == "pending" }) {
                    try services.persistence.shoppingListLines.performAndSave {
                        existingLine.desiredQty = max(existingLine.desiredQty, missingQty)
                    }
                } else {
                    _ = try services.persistence.shoppingListLines.create {
                        try ShoppingListLine(
                            inventoryItemId: item.id,
                            name: item.name,
                            desiredQty: missingQty,
                            status: "pending",
                            preferredMerchantId: merchantId(from: preferredMerchantTag),
                            list: list
                        )
                    }
                }
            }

            successMessage = "Added \(lowItems.count) item(s) to \(listName)."
            refresh()
        } catch {
            errorMessage = "Unable to merge low stock. \(error.localizedDescription)"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearSuccess() {
        successMessage = nil
    }

    func displayName(forMerchantTag tag: String) -> String {
        if let colon = tag.firstIndex(of: ":") {
            let raw = tag[tag.index(after: colon)...]
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let uuid = UUID(uuidString: trimmed),
               let services,
               let merchant = try? services.persistence.merchants.first(where: #Predicate { $0.id == uuid }) {
                return merchant.name
            }
            return trimmed.capitalized
        }
        return tag.capitalized
    }

    private func merchantId(from tag: String?) -> UUID? {
        guard let tag, let colon = tag.firstIndex(of: ":") else { return nil }
        let raw = tag[tag.index(after: colon)...]
        return UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Barcode Scanner Delegate

extension InventoryViewModel: BarcodeScannerDelegate {
    func barcodeScanner(_ scanner: PlatformViewController, didScan code: String) {
        addForm.barcode = code
        addForm.mode = .barcode
        Task { [weak self] in
            guard let self, let services = self.services else { return }
            let product = await services.barcode.lookupProduct(for: code)
            await MainActor.run {
                if let product {
                    if self.addForm.name.isEmpty {
                        self.addForm.name = product.name
                    }
                    if self.addForm.unit.isEmpty, let unit = product.unit {
                        self.addForm.unit = unit
                    }
                }
                self.dismissScanner()
            }
        }
    }

    func barcodeScannerDidCancel(_ scanner: PlatformViewController) {
        dismissScanner()
    }
}

// MARK: - View State Models

private struct InventoryLocationOption: Identifiable {
    let id: UUID?
    let name: String
}

private struct InventoryLocationViewState: Identifiable, Equatable {
    let id: UUID?
    let name: String
    let items: [InventoryItemViewState]
    let lowStockCount: Int
}

private struct InventoryItemViewState: Identifiable, Equatable {
    let id: UUID
    let name: String
    var qty: Double
    let unit: String
    let locationId: UUID?
    let locationName: String
    var expiry: Date?
    var restockThreshold: Double
    var lastPricePaid: Decimal?
    let tags: [String]
    let barcode: String?
    let isLowStock: Bool

    var quantityDisplay: String {
        "\(qty, specifier: "%.0f") \(unit)"
    }
}

private enum InventoryAddMode: String, CaseIterable, Identifiable {
    case manual
    case barcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .barcode:
            return "Barcode"
        }
    }
}

private struct InventoryAddItemForm {
    var mode: InventoryAddMode = .manual
    var barcode: String = ""
    var name: String = ""
    var quantity: Double = 1
    var unit: String = ""
    var restockThreshold: Double = 0
    var locationId: UUID? = nil
    var expiry: Date? = nil
    var hasExpiry: Bool = false
    var tags: String = ""
    var lastPricePaid: String = ""

    var tagArray: [String] {
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var lastPriceDecimal: Decimal? {
        let trimmed = lastPricePaid.trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: trimmed.replacingOccurrences(of: "$", with: ""))
    }
}

private extension InventoryAddItemForm {
    var resolvedExpiry: Date? {
        hasExpiry ? expiry : nil
    }
}

private extension Decimal {
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }

    var doubleValue: Double {
        (self as NSDecimalNumber).doubleValue
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

#Preview {
    InventoryView()
        .environment(\.services, ServiceContainer.makePreview())
}
