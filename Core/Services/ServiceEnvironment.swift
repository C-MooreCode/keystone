import SwiftUI

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue: ServiceContainer = ServiceContainer.makePreview()
}

extension EnvironmentValues {
    var services: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}

extension View {
    func services(_ services: ServiceContainer) -> some View {
        environment(\.services, services)
    }
}
