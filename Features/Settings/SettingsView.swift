import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.services) private var services
    @StateObject private var viewModel = SettingsViewModel()
    @State private var isImportingData = false

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

                Section("Data") {
                    Button {
                        viewModel.exportData()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.isPerformingDataTransfer)

                    Button {
                        isImportingData = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.isPerformingDataTransfer)
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            await viewModel.configureIfNeeded(syncService: services.sync, dataBackupService: services.dataBackup)
        }
        .fileExporter(
            isPresented: exportBinding,
            document: viewModel.exportDocument ?? .empty,
            contentType: .keystoneArchive,
            defaultFilename: viewModel.exportFilename
        ) { result in
            viewModel.finalizeExport(result: result)
        }
        .fileImporter(isPresented: $isImportingData, allowedContentTypes: [.keystoneArchive]) { result in
            switch result {
            case let .success(url):
                viewModel.importData(from: url)
            case let .failure(error):
                viewModel.handle(error: error)
            }
        }
        .alert("Settings Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .alert("Settings", isPresented: successBinding) {
            Button("OK", role: .cancel) {
                viewModel.clearSuccess()
            }
        } message: {
            Text(viewModel.successMessage ?? "")
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

    private var exportBinding: Binding<Bool> {
        Binding(
            get: { viewModel.exportDocument != nil },
            set: { value in
                if !value {
                    viewModel.cancelExport()
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { value in
                if !value {
                    viewModel.clearError()
                }
            }
        )
    }

    private var successBinding: Binding<Bool> {
        Binding(
            get: { viewModel.successMessage != nil },
            set: { value in
                if !value {
                    viewModel.clearSuccess()
                }
            }
        )
    }
}

#Preview {
    SettingsView()
        .environment(\.services, ServiceContainer.makePreview())
}
