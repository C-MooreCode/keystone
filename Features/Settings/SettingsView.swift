import SwiftUI

struct SettingsView: View {
    @Environment(\.services) private var services
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud") {
                    Toggle(isOn: Binding(
                        get: { viewModel.configuration.isEnabled },
                        set: { viewModel.toggleSync($0) }
                    )) {
                        Label("iCloud Sync", systemImage: "icloud")
                    }

                    statusRow

                    Button {
                        viewModel.syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(!viewModel.configuration.isEnabled || viewModel.status.isSyncing)
                }

                Section("Permissions") {
                    ForEach(viewModel.availableFeatures) { feature in
                        Toggle(isOn: Binding(
                            get: { viewModel.isFeatureEnabled(feature) },
                            set: { viewModel.toggleFeature(feature, isOn: $0) }
                        )) {
                            Label(feature.displayName, systemImage: feature.systemImageName)
                        }
                        .disabled(!viewModel.configuration.isEnabled)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            await viewModel.configureIfNeeded(syncService: services.sync)
        }
    }

    private var statusRow: some View {
        Label {
            Text(viewModel.statusDescription)
                .foregroundStyle(viewModel.statusColor)
                .font(.footnote)
        } icon: {
            Image(systemName: viewModel.statusIconName)
                .foregroundStyle(viewModel.statusColor)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
        .environment(\.services, ServiceContainer.makePreview())
}
