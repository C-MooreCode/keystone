import SwiftUI
import SwiftData

@main
struct KeystoneApp: App {
    @StateObject private var compositionRoot = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(compositionRoot.modelContainer)
                .environmentObject(compositionRoot.appStore)
                .environment(\.services, compositionRoot.services)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: store.selectedTabBinding) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(AppState.Tab.today)

            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray")
                }
                .tag(AppState.Tab.inbox)

            InventoryView()
                .tabItem {
                    Label("Inventory", systemImage: "shippingbox")
                }
                .tag(AppState.Tab.inventory)

            ShoppingView()
                .tabItem {
                    Label("Shopping", systemImage: "cart")
                }
                .tag(AppState.Tab.shopping)

            ExpensesView()
                .tabItem {
                    Label("Expenses", systemImage: "creditcard")
                }
                .tag(AppState.Tab.expenses)

            HabitsView()
                .tabItem {
                    Label("Habits", systemImage: "repeat")
                }
                .tag(AppState.Tab.habits)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppState.Tab.settings)
        }
    }
}
