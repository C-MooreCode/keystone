import Combine
import Foundation
import SwiftUI

struct AppReducer {
    let services: ServiceContainer
    let persistence: PersistenceController
    let syncService: SyncService

    func reduce(state: inout AppState, action: AppAction) {
        switch action {
        case let .selectTab(tab):
            state.selectedTab = tab
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state: AppState
    private let reducer: AppReducer

    init(initialState: AppState, reducer: AppReducer) {
        self.state = initialState
        self.reducer = reducer
    }

    func send(_ action: AppAction) {
        reducer.reduce(state: &state, action: action)
    }
}

extension AppStore {
    var selectedTabBinding: Binding<AppState.Tab> {
        Binding(
            get: { self.state.selectedTab },
            set: { self.send(.selectTab($0)) }
        )
    }

    func open(url: URL) {
        guard let deepLink = AppDeepLink(url: url) else { return }
        switch deepLink {
        case let .tab(tab):
            send(.selectTab(tab))
        }
    }
}
