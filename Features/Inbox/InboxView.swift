import Combine
import SwiftData
import SwiftUI

struct InboxView: View {
    @Environment(\.services) private var services
    @StateObject private var viewModel = InboxViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading inbox…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding()
                } else {
                    List {
                        if viewModel.items.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "Inbox is empty",
                                    systemImage: "tray",
                                    description: Text("Use the options below to send items to Keystone.")
                                )
                                .padding(.vertical, 24)
                            }
                        } else {
                            Section("Pending items") {
                                ForEach(viewModel.items) { item in
                                    InboxItemRow(
                                        item: item,
                                        classify: { viewModel.classify(item) },
                                        link: { viewModel.link(item) },
                                        dismiss: { viewModel.dismiss(item) }
                                    )
                                }
                            }
                        }

                        Section("Add via Share") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Use the Keystone share extension from apps like Safari, Mail, and Photos to send content straight to your inbox.")
                                Text("Scan paper receipts with the camera, or import spreadsheets from Files as CSV to capture transactions in bulk.")
                                Text("Shared items arrive here with automatic classifier suggestions so you can organise them quickly.")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inbox")
            .task {
                viewModel.configure(services: services)
                viewModel.refresh()
            }
            .alert("Inbox Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
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

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var services: ServiceContainer?
    private var eventSubscription: AnyCancellable?
    private var processedItemIds: Set<UUID> = []

    func configure(services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services
        subscribeToEvents(with: services)
    }

    func refresh() {
        guard let services else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let predicate = #Predicate<EventRecord> { record in
                record.kind == DomainEventKind.inboxEnqueued.rawValue
            }
            let records = try services.persistence.eventStore.fetch(
                predicate: predicate,
                sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
            )
            let mapped = records.compactMap { InboxItem(record: $0) }
            items = mapped.filter { !processedItemIds.contains($0.id) }
        } catch {
            errorMessage = "Unable to load inbox items. \(error.localizedDescription)"
        }
    }

    func classify(_ item: InboxItem) {
        postDecision(for: item, action: .classify)
    }

    func link(_ item: InboxItem) {
        postDecision(for: item, action: .link)
    }

    func dismiss(_ item: InboxItem) {
        guard let services else { return }

        do {
            let payload = InboxDismissedPayload(inboxItemId: item.id, reason: "user")
            let json = try jsonString(from: payload)
            try services.persistence.eventStore.append(
                kind: DomainEventKind.inboxDismissed.rawValue,
                payloadJSON: json,
                relatedIds: [item.id]
            )

            services.events.post(
                kind: .inboxDismissed,
                payload: [
                    "inboxItemId": item.id.uuidString,
                    "reason": payload.reason
                ]
            )

            markProcessed(item)
        } catch {
            errorMessage = "Unable to update inbox items. \(error.localizedDescription)"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    deinit {
        eventSubscription?.cancel()
    }

    private func subscribeToEvents(with services: ServiceContainer) {
        eventSubscription = services.persistence.eventStore.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] record in
                guard let self else { return }
                guard record.kind == DomainEventKind.inboxEnqueued.rawValue else { return }
                self.append(record)
            }
    }

    private func append(_ record: EventRecord) {
        guard !processedItemIds.contains(record.id),
              let item = InboxItem(record: record) else { return }

        if let existingIndex = items.firstIndex(where: { $0.id == item.id }) {
            items[existingIndex] = item
        } else {
            items.insert(item, at: 0)
        }
    }

    private func postDecision(for item: InboxItem, action: InboxAction) {
        guard let services else { return }

        do {
            let payload = InboxDecisionPayload(
                inboxItemId: item.id,
                action: action,
                classification: item.primarySuggestion
            )
            let json = try jsonString(from: payload)

            try services.persistence.eventStore.append(
                kind: DomainEventKind.inboxClassified.rawValue,
                payloadJSON: json,
                relatedIds: [item.id]
            )

            services.events.post(
                kind: .inboxClassified,
                payload: [
                    "inboxItemId": item.id.uuidString,
                    "action": action.rawValue,
                    "classification": item.primarySuggestion.rawValue
                ]
            )

            markProcessed(item)
        } catch {
            errorMessage = "Unable to update inbox items. \(error.localizedDescription)"
        }
    }

    private func markProcessed(_ item: InboxItem) {
        processedItemIds.insert(item.id)
        items.removeAll { $0.id == item.id }
    }

    private func jsonString<T: Encodable>(from value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Unable to encode JSON string.")
            )
        }
        return json
    }
}

struct InboxItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String?
    let receivedAt: Date
    let source: Source
    let suggestions: [InboxClassifierSuggestion]

    var primarySuggestion: InboxClassification {
        suggestions.first?.classification ?? .receipt
    }

    init?(record: EventRecord) {
        id = record.id
        receivedAt = record.occurredAt

        guard let data = record.payloadJSON.data(using: .utf8) else {
            title = "Incoming item"
            detail = nil
            source = .share
            suggestions = InboxClassification.allCases.map { InboxClassifierSuggestion(classification: $0) }
            return
        }

        do {
            let payload = try JSONDecoder().decode(InboxEventPayload.self, from: data)
            title = payload.title?.nonEmpty ?? "Incoming item"
            detail = payload.detail?.nonEmpty
            source = payload.source ?? .share
            if let payloadSuggestions = payload.suggestions {
                let mapped = payloadSuggestions.compactMap { $0.asSuggestion() }
                suggestions = mapped.isEmpty ? InboxClassification.defaultSuggestions : mapped
            } else {
                suggestions = InboxClassification.defaultSuggestions
            }
        } catch {
            title = "Incoming item"
            detail = nil
            source = .share
            suggestions = InboxClassification.defaultSuggestions
        }
    }

    static func == (lhs: InboxItem, rhs: InboxItem) -> Bool {
        lhs.id == rhs.id
    }

    enum Source: String, Codable {
        case share
        case camera
        case csv

        var iconName: String {
            switch self {
            case .share: "square.and.arrow.up"
            case .camera: "camera.fill"
            case .csv: "tablecells"
            }
        }

        var iconColor: Color {
            switch self {
            case .share: .blue
            case .camera: .green
            case .csv: .orange
            }
        }

        var displayName: String {
            switch self {
            case .share: "Shared"
            case .camera: "Camera"
            case .csv: "CSV"
            }
        }
    }
}

struct InboxClassifierSuggestion: Identifiable, Hashable {
    let classification: InboxClassification
    let confidence: Double?

    init(classification: InboxClassification, confidence: Double? = nil) {
        self.classification = classification
        self.confidence = confidence
    }

    init?(name: String, confidence: Double? = nil) {
        guard let classification = InboxClassification(rawValue: name.lowercased()) else { return nil }
        self.init(classification: classification, confidence: confidence)
    }

    var id: String { classification.rawValue }

    var displayName: String { classification.displayName }

    var iconName: String { classification.iconName }

    var confidenceLabel: String? {
        guard let confidence else { return nil }
        let percentage = NumberFormatter.percent.string(from: NSNumber(value: confidence))
        return percentage
    }
}

enum InboxClassification: String, Codable, CaseIterable {
    case receipt
    case note
    case csv

    var displayName: String {
        switch self {
        case .receipt: "Receipt"
        case .note: "Note"
        case .csv: "CSV"
        }
    }

    var iconName: String {
        switch self {
        case .receipt: "doc.text"
        case .note: "note.text"
        case .csv: "tablecells"
        }
    }

    static var defaultSuggestions: [InboxClassifierSuggestion] {
        allCases.map { InboxClassifierSuggestion(classification: $0) }
    }
}

enum InboxAction: String, Codable {
    case classify
    case link
}

private struct InboxDecisionPayload: Encodable {
    let inboxItemId: UUID
    let action: InboxAction
    let classification: InboxClassification
}

private struct InboxDismissedPayload: Encodable {
    let inboxItemId: UUID
    let reason: String
}

private struct InboxEventPayload: Decodable {
    let title: String?
    let detail: String?
    let source: InboxItem.Source?
    let suggestions: [InboxSuggestionPayload]?
}

private struct InboxSuggestionPayload: Decodable {
    let value: String?
    let confidence: Double?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let string = try? single.decode(String.self) {
            value = string
            confidence = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let classification = try container.decodeIfPresent(String.self, forKey: .classification)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        value = classification ?? label
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
    }

    private enum CodingKeys: String, CodingKey {
        case classification
        case label
        case confidence
    }

    func asSuggestion() -> InboxClassifierSuggestion? {
        guard let value else { return nil }
        return InboxClassifierSuggestion(name: value, confidence: confidence)
    }
}

private struct InboxItemRow: View {
    let item: InboxItem
    let classify: () -> Void
    let link: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SourceIcon(source: item.source)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.receivedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                    }
                }
                Spacer()
            }

            if !item.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Classifier suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SuggestionsView(suggestions: item.suggestions)
                }
            }

            HStack(spacing: 12) {
                Button("Classify", action: classify)
                    .buttonStyle(.borderedProminent)

                Button("Link", action: link)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Dismiss", role: .destructive, action: dismiss)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct SourceIcon: View {
    let source: InboxItem.Source

    var body: some View {
        Image(systemName: source.iconName)
            .font(.title3)
            .foregroundStyle(.white)
            .padding(10)
            .background(Circle().fill(source.iconColor))
            .accessibilityHidden(true)
    }
}

private struct SuggestionsView: View {
    let suggestions: [InboxClassifierSuggestion]

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(suggestions) { suggestion in
                HStack(spacing: 4) {
                    Image(systemName: suggestion.iconName)
                    Text(suggestion.displayName)
                    if let confidence = suggestion.confidenceLabel {
                        Text(confidence)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private extension NumberFormatter {
    static let percent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

#Preview {
    InboxView()
        .environment(\.services, ServiceContainer.inboxPreview())
}
