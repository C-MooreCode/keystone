import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Toggle(isOn: .constant(true)) {
                    Label("iCloud Sync", systemImage: "icloud")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
