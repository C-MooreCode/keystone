import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class ShareExtensionViewController: UIHostingController<ShareExtensionView> {
    private let viewModel = ShareExtensionViewModel()

    required init?(coder aDecoder: NSCoder) {
        let viewModel = ShareExtensionViewModel()
        let rootView = ShareExtensionView(viewModel: viewModel)
        super.init(coder: aDecoder, rootView: rootView)
        viewModel.configure(with: extensionContext)
    }

    override init(rootView: ShareExtensionView) {
        fatalError("init(rootView:) has not been implemented")
    }
}

struct ShareExtensionView: View {
    @ObservedObject var viewModel: ShareExtensionViewModel

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .preparing:
                ProgressView("Preparing…")
                    .progressViewStyle(.circular)
            case .processing:
                ProgressView("Saving to Inbox…")
                    .progressViewStyle(.circular)
            case .success(let message):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text(message)
                    .font(.headline)
                Text("You can continue in Keystone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .failure(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)
                Text("Unable to Share")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Dismiss") {
                    viewModel.cancel()
                }
            }
        }
        .padding()
        .onAppear {
            viewModel.beginProcessing()
        }
    }
}

@MainActor
final class ShareExtensionViewModel: ObservableObject {
    enum State {
        case preparing
        case processing
        case success(message: String)
        case failure(message: String)
    }

    @Published private(set) var state: State = .preparing

    private weak var extensionContext: NSExtensionContext?
    private var processingTask: Task<Void, Never>?
    private let handler: ShareExtensionHandler

    init(handler: ShareExtensionHandler = ShareExtensionHandler()) {
        self.handler = handler
    }

    func configure(with context: NSExtensionContext?) {
        guard let context else {
            state = .failure(message: "Missing extension context.")
            return
        }
        extensionContext = context
    }

    func beginProcessing() {
        guard processingTask == nil else { return }
        guard let context = extensionContext else { return }

        state = .processing
        processingTask = Task {
            do {
                let result = try await handler.process(context: context)
                state = .success(message: result.successMessage)
                try await Task.sleep(nanoseconds: 800_000_000)
                completeRequest()
            } catch {
                state = .failure(message: error.localizedDescription)
            }
        }
    }

    func cancel() {
        processingTask?.cancel()
        extensionContext?.cancelRequest(withError: ShareExtensionError.userCancelled)
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

struct ShareExtensionResult {
    let successMessage: String
}

enum ShareExtensionError: LocalizedError {
    case unsupportedContent
    case missingAppGroup
    case failedToSave
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            return "The shared items are not in a supported format."
        case .missingAppGroup:
            return "Shared storage could not be accessed."
        case .failedToSave:
            return "Keystone was unable to save the shared content."
        case .userCancelled:
            return "The share operation was cancelled."
        }
    }
}

struct ShareExtensionHandler {
    private struct LoadedAttachment {
        let data: Data
        let filename: String
        let fileExtension: String
        let uti: UTType
        let textPreview: String?
        let classification: SharedInboxSuggestion
    }

    private let supportedTypes: [UTType] = [
        .image,
        .pdf,
        .plainText,
        .commaSeparatedText
    ]

    private let queue: SharedInboxQueue

    init(queue: SharedInboxQueue = SharedInboxQueue()) {
        self.queue = queue
    }

    func process(context: NSExtensionContext) async throws -> ShareExtensionResult {
        let attachments = try await loadAttachments(from: context)
        guard !attachments.isEmpty else { throw ShareExtensionError.unsupportedContent }

        let savedAttachments: [SharedInboxAttachment]
        do {
            savedAttachments = try save(attachments)
        } catch let error as SharedInboxQueueError {
            throw mapQueueError(error)
        }
        let suggestions = suggestionsForAttachments(attachments)
        let title = savedAttachments.first?.filename
        let detail = attachments.compactMap { $0.textPreview?.inboxSnippet() }.first

        let inboxItem = SharedInboxItem(
            title: title,
            detail: detail,
            suggestions: Array(suggestions),
            attachments: savedAttachments
        )

        do {
            try queue.enqueue(inboxItem)
        } catch let error as SharedInboxQueueError {
            throw mapQueueError(error)
        }
        return ShareExtensionResult(successMessage: "Added to Inbox")
    }

    private func loadAttachments(from context: NSExtensionContext) async throws -> [LoadedAttachment] {
        guard let inputItems = context.inputItems as? [NSExtensionItem] else { return [] }
        var loaded: [LoadedAttachment] = []

        for item in inputItems {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if let attachment = try await loadAttachment(from: provider) {
                    loaded.append(attachment)
                }
            }
        }

        return loaded
    }

    private func loadAttachment(from provider: NSItemProvider) async throws -> LoadedAttachment? {
        for type in supportedTypes {
            if provider.hasItemConforming(toTypeIdentifier: type.identifier) {
                if let attachment = try await readAttachment(from: provider, type: type) {
                    return attachment
                }
            }
        }
        return nil
    }

    private func readAttachment(from provider: NSItemProvider, type: UTType) async throws -> LoadedAttachment? {
        if let url = try await provider.loadFileRepresentation(for: type) {
            return try makeAttachment(from: url, type: type)
        }

        if let data = try await provider.loadDataRepresentation(for: type) {
            return makeAttachment(from: data, suggestedName: provider.suggestedName, type: type)
        }

        if type == .plainText, let string = try await provider.loadText() {
            let data = Data(string.utf8)
            return makeAttachment(from: data, suggestedName: provider.suggestedName, type: type, textPreview: string)
        }

        return nil
    }

    private func makeAttachment(from url: URL, type: UTType) throws -> LoadedAttachment {
        let data: Data
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            data = try Data(contentsOf: url)
        } else {
            data = try Data(contentsOf: url)
        }

        let filename = url.lastPathComponent
        let fileExtension = url.pathExtension.nonEmpty ?? type.preferredFilenameExtension ?? "dat"
        let preview = type == .plainText ? String(data: data, encoding: .utf8) : nil
        return LoadedAttachment(
            data: data,
            filename: filename,
            fileExtension: fileExtension,
            uti: type,
            textPreview: preview,
            classification: classification(for: type)
        )
    }

    private func makeAttachment(from data: Data, suggestedName: String?, type: UTType, textPreview: String? = nil) -> LoadedAttachment {
        let fileExtension = type.preferredFilenameExtension ?? "dat"
        let filename = (suggestedName ?? UUID().uuidString) + "." + fileExtension
        let preview = textPreview ?? (type == .plainText ? String(data: data, encoding: .utf8) : nil)
        return LoadedAttachment(
            data: data,
            filename: filename,
            fileExtension: fileExtension,
            uti: type,
            textPreview: preview,
            classification: classification(for: type)
        )
    }

    private func save(_ attachments: [LoadedAttachment]) throws -> [SharedInboxAttachment] {
        guard !attachments.isEmpty else { return [] }
        let directory = try queue.attachmentsDirectoryURL()
        var saved: [SharedInboxAttachment] = []

        for attachment in attachments {
            let id = UUID()
            let filename = "\(id.uuidString).\(attachment.fileExtension)"
            let destination = directory.appendingPathComponent(filename)
            do {
                try attachment.data.write(to: destination, options: [.atomic])
            } catch {
                throw ShareExtensionError.failedToSave
            }

            let relativePath = "\(SharedInboxQueue.attachmentsDirectoryName)/\(filename)"
            let savedAttachment = SharedInboxAttachment(
                id: id,
                filename: attachment.filename,
                relativePath: relativePath,
                uniformTypeIdentifier: attachment.uti.identifier
            )
            saved.append(savedAttachment)
        }

        return saved
    }

    private func suggestionsForAttachments(_ attachments: [LoadedAttachment]) -> Set<SharedInboxSuggestion> {
        var suggestions: Set<SharedInboxSuggestion> = []
        for attachment in attachments {
            suggestions.insert(attachment.classification)
        }

        if suggestions.isEmpty {
            suggestions.insert(SharedInboxSuggestion(classification: "receipt"))
            suggestions.insert(SharedInboxSuggestion(classification: "note"))
            suggestions.insert(SharedInboxSuggestion(classification: "csv"))
        }

        return suggestions
    }

    private func classification(for type: UTType) -> SharedInboxSuggestion {
        if type.conforms(to: .commaSeparatedText) {
            return SharedInboxSuggestion(classification: "csv")
        } else if type.conforms(to: .plainText) {
            return SharedInboxSuggestion(classification: "note")
        } else {
            return SharedInboxSuggestion(classification: "receipt")
        }
    }

    private func mapQueueError(_ error: SharedInboxQueueError) -> ShareExtensionError {
        switch error {
        case .missingAppGroupContainer:
            return .missingAppGroup
        case .unavailableUserDefaults, .encodingFailed, .decodingFailed:
            return .failedToSave
        }
    }
}

private extension String {
    func inboxSnippet(maxLength: Int = 140) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        let prefix = trimmed[..<endIndex]
        return String(prefix) + "…"
    }
}

private extension NSItemProvider {
    func loadFileRepresentation(for type: UTType) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
        }
    }

    func loadDataRepresentation(for type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    func loadText() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
