import WidgetKit
import SwiftUI

struct KeystoneWidgetEntry: TimelineEntry {
    let date: Date
}

struct KeystoneWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> KeystoneWidgetEntry {
        KeystoneWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (KeystoneWidgetEntry) -> Void) {
        completion(KeystoneWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KeystoneWidgetEntry>) -> Void) {
        completion(Timeline(entries: [KeystoneWidgetEntry(date: .now)], policy: .atEnd))
    }
}

struct KeystoneWidgetEntryView: View {
    var entry: KeystoneWidgetEntry

    var body: some View {
        Text("Keystone Widget")
    }
}

struct KeystoneWidget: Widget {
    let kind: String = "KeystoneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KeystoneWidgetProvider()) { entry in
            KeystoneWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Keystone")
        .description("Quick glance at Keystone data.")
    }
}

#Preview(as: .systemSmall) {
    KeystoneWidget()
} timeline: {
    KeystoneWidgetEntry(date: .now)
}
