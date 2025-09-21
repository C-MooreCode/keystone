import AppIntents

struct KeystoneShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: OpenTodayIntent(),
                phrases: ["Open Today in Keystone"],
                shortTitle: "Today",
                systemImageName: "sun.max"
            ),
            AppShortcut(
                intent: LogExpenseIntent(),
                phrases: ["Log expense in Keystone"],
                shortTitle: "Log Expense",
                systemImageName: "creditcard"
            ),
            AppShortcut(
                intent: AddInventoryIntent(),
                phrases: ["Add inventory in Keystone"],
                shortTitle: "Add Inventory",
                systemImageName: "shippingbox"
            ),
            AppShortcut(
                intent: AdjustInventoryIntent(),
                phrases: ["Adjust stock in Keystone"],
                shortTitle: "Adjust Stock",
                systemImageName: "arrow.up.arrow.down"
            ),
            AppShortcut(
                intent: AddToShoppingListIntent(),
                phrases: ["Add shopping item in Keystone"],
                shortTitle: "Add to List",
                systemImageName: "cart.badge.plus"
            ),
            AppShortcut(
                intent: MarkBoughtIntent(),
                phrases: ["Mark shopping done in Keystone"],
                shortTitle: "Mark Bought",
                systemImageName: "cart.badge.checkmark"
            ),
            AppShortcut(
                intent: StartHabitIntent(),
                phrases: ["Start habit in Keystone"],
                shortTitle: "Start Habit",
                systemImageName: "flag"
            ),
            AppShortcut(
                intent: TickHabitIntent(),
                phrases: ["Tick habit in Keystone"],
                shortTitle: "Tick Habit",
                systemImageName: "checkmark.circle"
            ),
            AppShortcut(
                intent: WhatIsLowIntent(),
                phrases: ["What is low in Keystone"],
                shortTitle: "Low Stock",
                systemImageName: "chart.bar"
            ),
            AppShortcut(
                intent: ImportCSVIntent(),
                phrases: ["Import CSV in Keystone"],
                shortTitle: "Import CSV",
                systemImageName: "tray.and.arrow.down"
            ),
            AppShortcut(
                intent: RunRuleIntent(),
                phrases: ["Run rule in Keystone"],
                shortTitle: "Run Rule",
                systemImageName: "gearshape"
            )
        ]
    }
}

struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"

    func perform() async throws -> some IntentResult {
        // Intents will be routed through shared app store once available.
        return .result()
    }
}
