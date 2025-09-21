import AppIntents

struct KeystoneShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        [AppShortcut(intent: OpenTodayIntent(), phrases: ["Open Today in Keystone"], shortTitle: "Today", systemImageName: "sun.max")]
    }
}

struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"

    func perform() async throws -> some IntentResult {
        // Intents will be routed through shared app store once available.
        return .result()
    }
}
