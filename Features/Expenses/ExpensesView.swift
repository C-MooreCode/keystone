import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ExpensesView: View {
    @Environment(\.services) private var services
    @StateObject private var viewModel = ExpensesViewModel()
    @State private var isImportingCSV = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.ledgerSections.isEmpty {
                    ProgressView("Loading expenses…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List {
                        budgetSection
                        ledgerSection
                        merchantSection
                        toolsSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Expenses")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.beginReceiptScan()
                    } label: {
                        Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                    }
                    .accessibilityIdentifier("expenses-scan-receipt")

                    Button {
                        isImportingCSV = true
                    } label: {
                        Label("Import CSV", systemImage: "tray.and.arrow.down")
                    }
                    .accessibilityIdentifier("expenses-import-csv")
                }
            }
            .task {
                viewModel.configure(services: services)
                viewModel.refresh()
            }
            .alert("Expenses Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .alert("Expenses Updated", isPresented: successBinding) {
                Button("OK", role: .cancel) { viewModel.clearSuccess() }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
            .sheet(item: $viewModel.receiptScanner) { scanner in
                ReceiptScanSheet(viewModel: scanner) {
                    viewModel.cancelReceiptScan()
                } finish: {
                    viewModel.finishReceiptScan()
                }
            }
            .sheet(item: $viewModel.csvReviewModel) { model in
                CSVImportReviewSheet(viewModel: model) {
                    viewModel.dismissCSVReview()
                    viewModel.refresh()
                }
            }
            .sheet(item: $viewModel.editingEnvelope) { draft in
                BudgetEnvelopeEditor(draft: draft) { updatedDraft in
                    viewModel.saveEnvelope(draft: updatedDraft)
                } delete: { id in
                    viewModel.deleteEnvelope(id: id)
                } dismiss: {
                    viewModel.dismissEnvelopeEditor()
                }
            }
            .fileImporter(isPresented: $isImportingCSV, allowedContentTypes: [.commaSeparatedText]) { result in
                switch result {
                case let .success(url):
                    viewModel.prepareCSVReview(for: url)
                case let .failure(error):
                    viewModel.handle(error: error)
                }
            }
        }
    }

    private var budgetSection: some View {
        Section("Budget") {
            if let summary = viewModel.budgetSummary {
                BudgetSummaryCard(summary: summary)
                    .listRowInsets(EdgeInsets())
            }

            if viewModel.envelopes.isEmpty {
                ContentUnavailableView(
                    "No envelopes",
                    systemImage: "envelope", 
                    description: Text("Create envelopes to track your budget buckets.")
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.envelopes) { envelope in
                    Button {
                        viewModel.edit(envelope: envelope)
                    } label: {
                        BudgetEnvelopeRow(envelope: envelope)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                viewModel.addEnvelope()
            } label: {
                Label("Add Envelope", systemImage: "plus")
            }
        }
    }

    private var ledgerSection: some View {
        Section("Ledger") {
            if viewModel.ledgerSections.isEmpty {
                ContentUnavailableView(
                    "No transactions",
                    systemImage: "list.bullet.rectangle", 
                    description: Text("Scan receipts or import CSV files to build your ledger.")
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.ledgerSections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(section.date, style: .date)
                                .font(.headline)
                            Spacer()
                            Text(section.totalFormatted)
                                .font(.headline.monospacedDigit())
                        }
                        ForEach(section.entries) { entry in
                            LedgerEntryRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var merchantSection: some View {
        Section("Merchants") {
            if viewModel.merchantRollups.isEmpty {
                Text("No merchant rollups yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.merchantRollups) { rollup in
                    MerchantRollupRow(rollup: rollup)
                }
            }
        }
    }

    private var toolsSection: some View {
        Section("Tools") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Capture receipts, map CSV columns, and organise merchants to keep your ledger tidy.")
                Text("Envelopes automatically calculate what's left to spend using currency-safe rounding.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
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

// MARK: - Subviews

private struct BudgetSummaryCard: View {
    let summary: BudgetSummaryViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget left")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.remainingFormatted)
                        .font(.title.weight(.semibold))
                    Text("Spent \(summary.spentFormatted) of \(summary.limitFormatted)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if summary.limit > .zero {
                    ProgressView(value: summary.spentProgress)
                        .tint(.green)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .padding(.vertical, 4)
    }
}

private struct BudgetEnvelopeRow: View {
    let envelope: BudgetEnvelopeViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(envelope.name)
                    .font(.headline)
                Spacer()
                Text(envelope.remainingFormatted)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(envelope.remaining >= .zero ? .green : .red)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent \(envelope.spentFormatted) of \(envelope.limitFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !envelope.tags.isEmpty {
                        Text(envelope.tags.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ProgressView(value: envelope.spentProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct LedgerEntryRow: View {
    let entry: LedgerEntryViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.merchant)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.amountFormatted)
                    .font(.subheadline.monospacedDigit())
            }
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.tags.isEmpty {
                Text(entry.tags.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if entry.attachmentCount > 0 {
                Label(
                    "\(entry.attachmentCount) attachment\(entry.attachmentCount == 1 ? "" : "s")",
                    systemImage: "paperclip"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MerchantRollupRow: View {
    let rollup: MerchantRollupViewState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rollup.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(rollup.count) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(rollup.totalFormatted)
                .font(.body.monospacedDigit())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Receipt Scan

@MainActor
private final class ReceiptScanViewModel: ObservableObject, Identifiable {
    enum Step: Equatable {
        case capture
        case scanning
        case review
        case error(String)
        case completed
    }

    let id = UUID()

    @Published var step: Step = .capture
    @Published var selectedItem: PhotosPickerItem?
    @Published var review: ReceiptReviewState?
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let services: ServiceContainer
    private var imageData: Data?

    init(services: ServiceContainer) {
        self.services = services
    }

    func reset() {
        step = .capture
        review = nil
        selectedItem = nil
        imageData = nil
        errorMessage = nil
    }

    func processSelection() {
        guard let selectedItem else { return }
        Task { await loadImage(from: selectedItem) }
    }

    func retry() {
        reset()
    }

    func save() {
        guard let review, let data = imageData else { return }
        guard let amount = review.amount else {
            errorMessage = "Enter a valid amount before saving."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let attachmentURL = try services.persistence.storeAttachment(data: data, fileExtension: "jpg")
            let attachment = try services.persistence.attachments.create {
                try Attachment(kind: "receipt", localURL: attachmentURL, ocrText: review.ocrText)
            }

            let merchantId = try ensureMerchant(named: review.merchant)
            _ = try services.persistence.transactions.create {
                try Transaction(
                    amount: amount,
                    currency: review.currency,
                    date: review.date,
                    merchantId: merchantId,
                    tags: review.tags,
                    source: "receipt.scan",
                    attachmentIds: [attachment.id]
                )
            }

            services.budgetPublisher.refresh()
            step = .completed
        } catch {
            errorMessage = "Failed to save receipt. \(error.localizedDescription)"
            step = .error(error.localizedDescription)
        }
    }

    private func ensureMerchant(named name: String?) throws -> UUID? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try services.persistence.merchants.first(where: #Predicate { merchant in
            merchant.name == trimmed
        }) {
            return existing.id
        }
        let merchant = try services.persistence.merchants.create {
            try Merchant(name: trimmed)
        }
        return merchant.id
    }

    private func loadImage(from item: PhotosPickerItem) async {
        step = .scanning
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                imageData = data
                try await performOCR(on: data)
            } else {
                throw CocoaError(.fileReadCorruptFile)
            }
        } catch {
            errorMessage = "Unable to load image. \(error.localizedDescription)"
            step = .error(error.localizedDescription)
        }
    }

    private func performOCR(on data: Data) async throws {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            throw VisionOCRError.invalidImage
        }
        let result = try await services.vision.scan(image: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            throw VisionOCRError.invalidImage
        }
        let result = try await services.vision.scan(image: image)
        #else
        let temporaryURL = services.persistence.attachmentURL(for: UUID(), fileExtension: "jpg")
        try data.write(to: temporaryURL)
        let result = try await services.vision.scan(at: temporaryURL)
        #endif
        await MainActor.run {
            review = ReceiptReviewState(result: result, currency: Locale.current.currency?.identifier ?? "USD")
            step = .review
        }
    }
}

private struct ReceiptReviewState: Identifiable {
    let id = UUID()
    var merchant: String
    var amount: Decimal?
    var date: Date
    var currency: String
    var note: String
    var tags: [String]
    var ocrText: String?

    init(result: VisionOCRResult, currency: String) {
        merchant = result.merchant.value ?? ""
        amount = result.total.value
        date = result.date.value ?? .now
        self.currency = currency
        note = ""
        tags = ["receipt"]
        if !result.lineItems.isEmpty {
            let lines = result.lineItems.compactMap { item -> String? in
                guard let name = item.name.value else { return nil }
                let quantity = item.quantity.value.map { "\($0)" } ?? ""
                let price = item.price.value.map { "\($0)" } ?? ""
                return [name, quantity, price].filter { !$0.isEmpty }.joined(separator: " ")
            }
            ocrText = lines.joined(separator: "\n")
        } else {
            ocrText = nil
        }
    }
}

private struct ReceiptScanSheet: View {
    @ObservedObject var viewModel: ReceiptScanViewModel
    let cancel: () -> Void
    let finish: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch viewModel.step {
                case .capture:
                    captureStep
                case .scanning:
                    ProgressView("Scanning receipt…")
                case .review:
                    reviewStep
                case let .error(message):
                    VStack(spacing: 12) {
                        Text("Scan failed")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Try Again") { viewModel.retry() }
                    }
                case .completed:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("Receipt saved")
                            .font(.headline)
                        Button("Done") { finish() }
                    }
                }
            }
            .padding()
            .navigationTitle("Receipt Scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { cancel() }
                }
            }
        }
        .onChange(of: viewModel.selectedItem) { _, _ in
            viewModel.processSelection()
        }
    }

    private var captureStep: some View {
        VStack(spacing: 12) {
            Text("Capture a receipt photo or pick from your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PhotosPicker(
                selection: $viewModel.selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choose Photo", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var reviewStep: some View {
        Form {
            if let review = viewModel.review {
                Section("Details") {
                    TextField("Merchant", text: binding(for: \ReceiptReviewState.merchant))
                    TextField("Amount", text: Binding(
                        get: {
                            if let amount = review.amount {
                                return (amount as NSDecimalNumber).stringValue
                            }
                            return ""
                        },
                        set: { newValue in
                            if let decimal = Decimal(string: newValue.replacingOccurrences(of: "$", with: "")) {
                                viewModel.review?.amount = decimal
                            }
                        }
                    ))
                    DatePicker("Date", selection: binding(for: \ReceiptReviewState.date), displayedComponents: .date)
                    TextField("Currency", text: binding(for: \ReceiptReviewState.currency))
                    TextField("Note", text: binding(for: \ReceiptReviewState.note))
                }

                Section("Tags") {
                    TextField("Comma separated", text: Binding(
                        get: { review.tags.joined(separator: ", ") },
                        set: { newValue in
                            viewModel.review?.tags = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                    ))
                }

                if let ocr = review.ocrText, !ocr.isEmpty {
                    Section("OCR Items") {
                        Text(ocr)
                            .font(.caption)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.save()
            } label: {
                Text("Create Transaction")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .disabled(viewModel.isSaving)
        }
    }

    private func binding<Value>(for keyPath: WritableKeyPath<ReceiptReviewState, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.review?[keyPath: keyPath] ?? defaultValue(for: keyPath) },
            set: { newValue in viewModel.review?[keyPath: keyPath] = newValue }
        )
    }

    private func defaultValue<Value>(for keyPath: WritableKeyPath<ReceiptReviewState, Value>) -> Value {
        switch keyPath {
        case \ReceiptReviewState.merchant:
            return "" as! Value
        case \ReceiptReviewState.amount:
            return nil as! Value
        case \ReceiptReviewState.date:
            return Date() as! Value
        case \ReceiptReviewState.currency:
            return (Locale.current.currency?.identifier ?? "USD") as! Value
        case \ReceiptReviewState.note:
            return "" as! Value
        case \ReceiptReviewState.tags:
            return [] as! Value
        case \ReceiptReviewState.ocrText:
            return nil as! Value
        default:
            fatalError("Unhandled key path")
        }
    }
}

// MARK: - CSV Import

@MainActor
private final class CSVImportReviewModel: ObservableObject, Identifiable {
    struct CSVColumnMapping: Equatable {
        var date: Int?
        var description: Int?
        var amount: Int?

        var isComplete: Bool {
            date != nil && description != nil && amount != nil
        }
    }

    let id = UUID()
    @Published var mapping: CSVColumnMapping
    @Published var dateFormat: String
    @Published var currencyCode: String
    @Published private(set) var preview: [CSVTransactionRecord] = []
    @Published var errorMessage: String?

    let columns: [String]
    let dateFormatOptions: [String]

    private let rows: [[String]]
    private let onConfirm: ([CSVTransactionRecord], String) -> Void

    init(columns: [String], rows: [[String]], defaultCurrency: String, onConfirm: @escaping ([CSVTransactionRecord], String) -> Void) {
        self.columns = columns
        self.rows = rows
        self.onConfirm = onConfirm
        self.dateFormatOptions = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "MMM d, yyyy"]
        self.dateFormat = self.dateFormatOptions.first ?? "yyyy-MM-dd"
        self.currencyCode = defaultCurrency
        self.mapping = CSVColumnMapping()
        recalculatePreview()
    }

    func updateMapping(_ mapping: CSVColumnMapping) {
        self.mapping = mapping
        recalculatePreview()
    }

    func updateDateFormat(_ format: String) {
        dateFormat = format
        recalculatePreview()
    }

    func updateCurrency(_ currency: String) {
        currencyCode = currency.uppercased()
    }

    @discardableResult
    func confirm() -> Bool {
        guard errorMessage == nil else { return false }
        guard mapping.isComplete else {
            errorMessage = "Select columns for date, description, and amount."
            return false
        }
        guard !preview.isEmpty else {
            errorMessage = "No rows could be parsed with the selected mapping."
            return false
        }
        onConfirm(preview, currencyCode)
        return true
    }

    private func recalculatePreview() {
        guard mapping.isComplete else {
            preview = []
            errorMessage = "Select columns to parse the CSV."
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var parsed: [CSVTransactionRecord] = []
        for row in rows {
            guard let dateIndex = mapping.date, dateIndex < row.count,
                  let descriptionIndex = mapping.description, descriptionIndex < row.count,
                  let amountIndex = mapping.amount, amountIndex < row.count else { continue }

            let dateString = row[dateIndex]
            let description = row[descriptionIndex]
            let amountString = row[amountIndex]

            guard let date = formatter.date(from: dateString) else { continue }
            guard let amount = decimal(from: amountString) else { continue }

            parsed.append(CSVTransactionRecord(date: date, description: description, amount: amount))
        }

        preview = parsed
        errorMessage = parsed.isEmpty ? "No rows could be parsed with the selected mapping." : nil
    }

    private func decimal(from string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        return Decimal(string: sanitized)
    }
}

private struct CSVImportReviewSheet: View {
    @ObservedObject var viewModel: CSVImportReviewModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Column Mapping") {
                    Picker("Date", selection: Binding(
                        get: { viewModel.mapping.date ?? -1 },
                        set: { viewModel.updateMapping(CSVImportReviewModel.CSVColumnMapping(
                            date: $0 >= 0 ? $0 : nil,
                            description: viewModel.mapping.description,
                            amount: viewModel.mapping.amount
                        )) }
                    )) {
                        Text("Select column").tag(-1)
                        ForEach(Array(viewModel.columns.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }

                    Picker("Description", selection: Binding(
                        get: { viewModel.mapping.description ?? -1 },
                        set: { viewModel.updateMapping(CSVImportReviewModel.CSVColumnMapping(
                            date: viewModel.mapping.date,
                            description: $0 >= 0 ? $0 : nil,
                            amount: viewModel.mapping.amount
                        )) }
                    )) {
                        Text("Select column").tag(-1)
                        ForEach(Array(viewModel.columns.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }

                    Picker("Amount", selection: Binding(
                        get: { viewModel.mapping.amount ?? -1 },
                        set: { viewModel.updateMapping(CSVImportReviewModel.CSVColumnMapping(
                            date: viewModel.mapping.date,
                            description: viewModel.mapping.description,
                            amount: $0 >= 0 ? $0 : nil
                        )) }
                    )) {
                        Text("Select column").tag(-1)
                        ForEach(Array(viewModel.columns.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                }

                Section("Options") {
                    Picker("Date Format", selection: Binding(
                        get: { viewModel.dateFormat },
                        set: { viewModel.updateDateFormat($0) }
                    )) {
                        ForEach(viewModel.dateFormatOptions, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }
                    TextField("Currency", text: Binding(
                        get: { viewModel.currencyCode },
                        set: { viewModel.updateCurrency($0) }
                    ))
                }

                Section("Preview") {
                    if viewModel.preview.isEmpty {
                        Text(viewModel.errorMessage ?? "Select a mapping to preview records.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.preview.enumerated()), id: \.offset) { index, record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.description)
                                    .font(.subheadline.weight(.semibold))
                                Text(record.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text((record.amount as NSDecimalNumber).stringValue)
                                    .font(.caption.monospacedDigit())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Review CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if viewModel.confirm() {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.preview.isEmpty)
                }
            }
        }
    }
}

// MARK: - Budget Envelope Editor

private struct BudgetEnvelopeDraft: Identifiable {
    let id: UUID?
    var name: String
    var limit: String
    var currency: String
    var tags: String
    var notes: String

    init(envelope: BudgetEnvelopeViewState) {
        id = envelope.id
        name = envelope.name
        limit = (envelope.limit as NSDecimalNumber).stringValue
        currency = envelope.currency
        tags = envelope.tags.joined(separator: ", ")
        notes = envelope.notes ?? ""
    }

    init(defaultCurrency: String) {
        id = nil
        name = ""
        limit = "0"
        currency = defaultCurrency
        tags = ""
        notes = ""
    }
}

private struct BudgetEnvelopeEditor: View {
    @State private var draft: BudgetEnvelopeDraft
    let save: (BudgetEnvelopeDraft) -> Void
    let delete: (UUID) -> Void
    let dismiss: () -> Void

    init(draft: BudgetEnvelopeDraft, save: @escaping (BudgetEnvelopeDraft) -> Void, delete: @escaping (UUID) -> Void, dismiss: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.save = save
        self.delete = delete
        self.dismiss = dismiss
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Envelope") {
                    TextField("Name", text: $draft.name)
                    TextField("Monthly Limit", text: $draft.limit)
                    TextField("Currency", text: $draft.currency)
                }
                Section("Tags") {
                    TextField("Comma separated", text: $draft.tags)
                }
                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                }
                if let id = draft.id {
                    Section {
                        Button(role: .destructive) {
                            delete(id)
                            dismiss()
                        } label: {
                            Text("Delete Envelope")
                        }
                    }
                }
            }
            .navigationTitle(draft.id == nil ? "New Envelope" : "Edit Envelope")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class ExpensesViewModel: ObservableObject {
    @Published var ledgerSections: [LedgerSectionViewState] = []
    @Published var merchantRollups: [MerchantRollupViewState] = []
    @Published var envelopes: [BudgetEnvelopeViewState] = []
    @Published var budgetSummary: BudgetSummaryViewState?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var receiptScanner: ReceiptScanViewModel?
    @Published var csvReviewModel: CSVImportReviewModel?
    @Published var editingEnvelope: BudgetEnvelopeDraft?

    private var services: ServiceContainer?
    private var budgetSubscription: AnyCancellable?
    private var envelopeModels: [UUID: BudgetEnvelope] = [:]
    private var latestSummary: BudgetSummary = .empty()

    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }

    func configure(services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services
        budgetSubscription = services.budgetPublisher.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                self?.latestSummary = summary
                self?.applyBudgetSummary()
            }
        services.budgetPublisher.refresh()
    }

    func refresh() {
        guard let services else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try loadLedger(using: services)
            try loadEnvelopes(using: services)
        } catch {
            errorMessage = "Failed to load expenses. \(error.localizedDescription)"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearSuccess() {
        successMessage = nil
    }

    func beginReceiptScan() {
        guard let services else { return }
        let scanner = ReceiptScanViewModel(services: services)
        receiptScanner = scanner
    }

    func cancelReceiptScan() {
        receiptScanner = nil
    }

    func finishReceiptScan() {
        receiptScanner = nil
        services?.budgetPublisher.refresh()
        refresh()
        successMessage = "Receipt saved."
    }

    func prepareCSVReview(for url: URL) {
        guard let services else { return }
        do {
            let parser = CSVParser()
            let rows = try parser.parse(url: url)
            guard let header = rows.first else {
                throw CSVImportError.missingField("header")
            }
            let dataRows = Array(rows.dropFirst())
            csvReviewModel = CSVImportReviewModel(
                columns: header,
                rows: dataRows,
                defaultCurrency: Locale.current.currency?.identifier ?? "USD"
            ) { [weak self] records, currency in
                self?.importTransactions(records, currency: currency)
            }
        } catch {
            errorMessage = "Unable to read CSV. \(error.localizedDescription)"
        }
    }

    func dismissCSVReview() {
        csvReviewModel = nil
    }

    func handle(error: Error) {
        errorMessage = error.localizedDescription
    }

    func addEnvelope() {
        let draft = BudgetEnvelopeDraft(defaultCurrency: Locale.current.currency?.identifier ?? "USD")
        editingEnvelope = draft
    }

    func edit(envelope: BudgetEnvelopeViewState) {
        editingEnvelope = BudgetEnvelopeDraft(envelope: envelope)
    }

    func dismissEnvelopeEditor() {
        editingEnvelope = nil
    }

    func saveEnvelope(draft: BudgetEnvelopeDraft) {
        guard let services else { return }
        do {
            let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let limit = parseDecimal(from: draft.limit), limit > 0 else {
                errorMessage = "Enter a valid monthly limit."
                return
            }
            let currency = draft.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let tags = draft.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)

            if let id = draft.id, let existing = envelopeModels[id] {
                try services.persistence.budgetEnvelopes.performAndSave {
                    existing.name = trimmedName
                    existing.monthlyLimit = limit
                    existing.currency = currency
                    existing.tags = tags
                    existing.notes = notes.isEmpty ? nil : notes
                }
            } else {
                _ = try services.persistence.budgetEnvelopes.create {
                    try BudgetEnvelope(
                        name: trimmedName,
                        monthlyLimit: limit,
                        currency: currency,
                        tags: tags,
                        notes: notes.isEmpty ? nil : notes
                    )
                }
            }
            services.budgetPublisher.refresh()
            refresh()
            successMessage = "Envelope saved."
        } catch {
            errorMessage = "Unable to save envelope. \(error.localizedDescription)"
        }
    }

    func deleteEnvelope(id: UUID) {
        guard let services else { return }
        do {
            if let envelope = envelopeModels[id] {
                try services.persistence.budgetEnvelopes.delete(envelope)
                envelopeModels.removeValue(forKey: id)
                services.budgetPublisher.refresh()
                refresh()
                successMessage = "Envelope deleted."
            }
        } catch {
            errorMessage = "Unable to delete envelope. \(error.localizedDescription)"
        }
    }

    private func loadLedger(using services: ServiceContainer) throws {
        let transactions = try services.persistence.transactions.fetch(
            sortBy: [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.amount, order: .reverse)
            ]
        )
        let merchants = try services.persistence.merchants.fetch()
        let merchantLookup = Dictionary(uniqueKeysWithValues: merchants.map { ($0.id, $0) })

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }

        ledgerSections = grouped.keys.sorted(by: >).map { date in
            let entries = grouped[date, default: []].map { transaction -> LedgerEntryViewState in
                let merchant = transaction.merchantId.flatMap { merchantLookup[$0]?.name } ?? "Unassigned"
                return LedgerEntryViewState(
                    id: transaction.id,
                    merchant: merchant,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    date: transaction.date,
                    note: transaction.source,
                    tags: transaction.tags,
                    attachmentCount: transaction.attachmentIds.count
                )
            }
            let total = CurrencyMath.sum(entries.map(\.amount))
            return LedgerSectionViewState(date: date, currency: entries.first?.currency ?? Locale.current.currency?.identifier ?? "USD", total: total, entries: entries)
        }
        .sorted { $0.date > $1.date }

        var rollupTotals: [UUID?: (name: String, total: Decimal, count: Int, currency: String)] = [:]
        for transaction in transactions {
            let key = transaction.merchantId
            var current = rollupTotals[key] ?? (
                name: key.flatMap { merchantLookup[$0]?.name } ?? "Unassigned",
                total: .zero,
                count: 0,
                currency: transaction.currency
            )
            current.total = current.total.currencyAdding(transaction.amount)
            current.count += 1
            current.currency = transaction.currency
            rollupTotals[key] = current
        }

        merchantRollups = rollupTotals.values.map { value in
            MerchantRollupViewState(name: value.name, total: value.total, count: value.count, currency: value.currency)
        }
        .sorted { $0.total > $1.total }
    }

    private func loadEnvelopes(using services: ServiceContainer) throws {
        let envelopes = try services.persistence.budgetEnvelopes.fetch(sortBy: [SortDescriptor(\.name, order: .forward)])
        envelopeModels = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.id, $0) })
        applyBudgetSummary()
    }

    private func applyBudgetSummary() {
        let summaryLookup = Dictionary(uniqueKeysWithValues: latestSummary.envelopes.map { ($0.id, $0) })
        envelopes = envelopeModels.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { envelope in
                let breakdown = summaryLookup[envelope.id]
                return BudgetEnvelopeViewState(
                    id: envelope.id,
                    name: envelope.name,
                    limit: envelope.monthlyLimit,
                    spent: breakdown?.spent ?? .zero,
                    remaining: breakdown?.remaining ?? envelope.monthlyLimit,
                    currency: envelope.currency,
                    tags: envelope.tags,
                    notes: envelope.notes
                )
            }
        if !latestSummary.envelopes.isEmpty {
            budgetSummary = BudgetSummaryViewState(summary: latestSummary)
        } else {
            budgetSummary = nil
        }
    }

    private func parseDecimal(from string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        return Decimal(string: sanitized)
    }

    private func importTransactions(_ records: [CSVTransactionRecord], currency: String) {
        guard let services else { return }
        guard !records.isEmpty else { return }

        do {
            for record in records {
                let merchantId = try ensureMerchant(named: record.description, services: services)
                _ = try services.persistence.transactions.create {
                    try Transaction(
                        amount: record.amount,
                        currency: currency,
                        date: record.date,
                        merchantId: merchantId,
                        tags: [],
                        source: "csv.import",
                        attachmentIds: []
                    )
                }
            }
            services.budgetPublisher.refresh()
            successMessage = "Imported \(records.count) transaction(s)."
            refresh()
        } catch {
            errorMessage = "Unable to import transactions. \(error.localizedDescription)"
        }
    }

    private func ensureMerchant(named description: String, services: ServiceContainer) throws -> UUID? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = try services.persistence.merchants.first(where: #Predicate { merchant in
            merchant.name == trimmed
        }) {
            return existing.id
        }
        let merchant = try services.persistence.merchants.create {
            try Merchant(name: trimmed)
        }
        return merchant.id
    }
}

// MARK: - View State

struct LedgerSectionViewState: Identifiable {
    let id = UUID()
    let date: Date
    let currency: String
    let total: Decimal
    let entries: [LedgerEntryViewState]

    var totalFormatted: String {
        formattedCurrency(total, currency: currency)
    }
}

struct LedgerEntryViewState: Identifiable {
    let id: UUID
    let merchant: String
    let amount: Decimal
    let currency: String
    let date: Date
    let note: String?
    let tags: [String]
    let attachmentCount: Int

    var amountFormatted: String {
        formattedCurrency(amount, currency: currency)
    }
}

struct MerchantRollupViewState: Identifiable {
    let id = UUID()
    let name: String
    let total: Decimal
    let count: Int
    let currency: String

    var totalFormatted: String {
        formattedCurrency(total, currency: currency)
    }
}

struct BudgetEnvelopeViewState: Identifiable {
    let id: UUID
    let name: String
    let limit: Decimal
    let spent: Decimal
    let remaining: Decimal
    let currency: String
    let tags: [String]
    let notes: String?

    var limitFormatted: String {
        formattedCurrency(limit, currency: currency)
    }

    var spentFormatted: String {
        formattedCurrency(spent, currency: currency)
    }

    var remainingFormatted: String {
        formattedCurrency(remaining, currency: currency)
    }

    var spentProgress: Double {
        guard limit > .zero else { return 0 }
        let ratio = spent.currencyDividing(by: limit, scale: 4)
        return min(max((ratio as NSDecimalNumber).doubleValue, 0), 1)
    }
}

struct BudgetSummaryViewState {
    let limit: Decimal
    let spent: Decimal
    let remaining: Decimal
    let currency: String

    init(summary: BudgetSummary) {
        limit = summary.totalLimit
        spent = summary.totalSpent
        remaining = summary.totalRemaining
        currency = summary.currency
    }

    var limitFormatted: String { formattedCurrency(limit, currency: currency) }
    var spentFormatted: String { formattedCurrency(spent, currency: currency) }
    var remainingFormatted: String { formattedCurrency(remaining, currency: currency) }

    var spentProgress: Double {
        guard limit > .zero else { return 0 }
        let ratio = spent.currencyDividing(by: limit, scale: 4)
        return min(max((ratio as NSDecimalNumber).doubleValue, 0), 1)
    }
}

private func formattedCurrency(_ value: Decimal, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}
