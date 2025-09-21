import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var configuration: SyncConfiguration
    @Published private(set) var status: SyncStatus

    private var syncService: SyncService?
    private var configurationTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private let relativeFormatter: RelativeDateTimeFormatter

    init(configuration: SyncConfiguration = SyncConfiguration(), status: SyncStatus = .disabled) {
        self.configuration = configuration
        self.status = status
        self.relativeFormatter = RelativeDateTimeFormatter()
        self.relativeFormatter.unitsStyle = .abbreviated
    }

    deinit {
        configurationTask?.cancel()
        statusTask?.cancel()
    }

    var availableFeatures: [SyncFeature] {
        SyncFeature.allCases
    }

    func configureIfNeeded(syncService: SyncService) async {
        guard self.syncService == nil else { return }
        self.syncService = syncService
        configuration = await syncService.currentConfiguration()
        status = await syncService.currentStatus()

        configurationTask = Task { [weak self] in
            let stream = await syncService.configurationStream()
            for await configuration in stream {
                await MainActor.run {
                    self?.configuration = configuration
                }
            }
        }

        statusTask = Task { [weak self] in
            let stream = await syncService.statusStream()
            for await status in stream {
                await MainActor.run {
                    self?.status = status
                }
            }
        }
    }

    func toggleSync(_ isOn: Bool) {
        configuration.setEnabled(isOn)
        Task { [weak self] in
            guard let self, let syncService = self.syncService else { return }
            await syncService.setSyncEnabled(isOn)
            if isOn {
                await syncService.synchronize()
            }
        }
    }

    func toggleFeature(_ feature: SyncFeature, isOn: Bool) {
        configuration.setFeature(feature, enabled: isOn)
        Task { [weak self] in
            guard let self, let syncService = self.syncService else { return }
            await syncService.setFeature(feature, enabled: isOn)
        }
    }

    func syncNow() {
        Task { [weak self] in
            guard let self, let syncService = self.syncService else { return }
            await syncService.synchronize()
        }
    }

    func isFeatureEnabled(_ feature: SyncFeature) -> Bool {
        configuration.allows(feature)
    }

    var statusDescription: String {
        switch status {
        case .disabled:
            return "Sync is turned off."
        case .syncing:
            return "Syncing with iCloud…"
        case let .idle(lastSync):
            if let lastSync {
                return "Last synced \(relativeFormatter.localizedString(for: lastSync, relativeTo: .now))."
            } else {
                return "Awaiting first sync."
            }
        case let .error(message, lastSync):
            if let lastSync {
                let relative = relativeFormatter.localizedString(for: lastSync, relativeTo: .now)
                return "Error: \(message). Last successful sync \(relative)."
            } else {
                return "Error: \(message)."
            }
        }
    }

    var statusIconName: String {
        switch status {
        case .disabled:
            return "icloud.slash"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .idle:
            return "checkmark.icloud"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var statusColor: Color {
        switch status {
        case .disabled:
            return .secondary
        case .syncing:
            return .accentColor
        case .idle:
            return .secondary
        case .error:
            return .red
        }
    }
}
