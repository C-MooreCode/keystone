#if canImport(ActivityKit)
import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@available(iOS 17.0, *)
struct StoreTripActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StoreTripActivityAttributes.self) { context in
            StoreTripActivityContentView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.storeName)
                            .font(.headline)
                        ProgressView(value: context.state.completionProgress) {
                            Text("Completed")
                                .font(.caption2)
                        }
                        .progressViewStyle(.linear)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("\(context.state.completedItems)", systemImage: "checkmark")
                            .font(.caption)
                        Label("\(context.state.pendingItems)", systemImage: "clock")
                            .font(.caption)
                    }
                }
            } compactLeading: {
                Text("\(context.state.completedItems)")
                    .font(.caption)
            } compactTrailing: {
                Text("\(max(context.state.pendingItems, 0))")
                    .font(.caption)
            } minimal: {
                Image(systemName: "cart")
            }
        }
    }
}

@available(iOS 17.0, *)
private struct StoreTripActivityContentView: View {
    let context: ActivityViewContext<StoreTripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                    Text(context.attributes.storeName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "cart")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }

            ProgressView(value: context.state.completionProgress) {
                Text("Progress")
                    .font(.caption)
            }
            .progressViewStyle(.linear)

            HStack {
                Label("Done \(context.state.completedItems)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                Spacer()
                Label("Left \(context.state.pendingItems)", systemImage: "list.bullet")
                    .font(.caption)
            }
        }
        .padding()
    }
}

@available(iOS 17.0, *)
struct FocusSessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusSessionActivityAttributes.self) { context in
            FocusSessionActivityContentView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    FocusSessionTimerView(context: context)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Text(timerLabel(for: context))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }

    private func timerLabel(for context: ActivityViewContext<FocusSessionActivityAttributes>) -> String {
        let remaining = max(0, Int(context.state.endDate.timeIntervalSince(Date())))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@available(iOS 17.0, *)
private struct FocusSessionActivityContentView: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context.attributes.title)
                .font(.headline)

            FocusSessionTimerView(context: context)
        }
        .padding()
    }
}

@available(iOS 17.0, *)
private struct FocusSessionTimerView: View {
    let context: ActivityViewContext<FocusSessionActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.state.habitName)
                .font(.subheadline)
            Text(timerInterval: context.state.timerRange, countsDown: true)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.tint)
            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
        }
    }
}

@available(iOS 17.0, *)
private struct StoreTripActivityPreview: ActivityPreviewContext {
    static var previewAttributes: StoreTripActivityAttributes {
        StoreTripActivityAttributes(
            listId: UUID(),
            storeName: "Neighborhood Market",
            title: "Saturday Groceries"
        )
    }

    static var contentState: StoreTripActivityAttributes.ContentState {
        StoreTripActivityAttributes.ContentState(
            totalItems: 12,
            completedItems: 4,
            pendingItems: 8
        )
    }
}

@available(iOS 17.0, *)
private struct FocusSessionActivityPreview: ActivityPreviewContext {
    static var previewAttributes: FocusSessionActivityAttributes {
        FocusSessionActivityAttributes(
            habitId: UUID(),
            title: "Deep Work"
        )
    }

    static var contentState: FocusSessionActivityAttributes.ContentState {
        FocusSessionActivityAttributes.ContentState(
            habitName: "Writing",
            targetSeconds: 1800,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800)
        )
    }
}

@available(iOS 17.0, *)
#Preview("Store Trip", as: .content, using: StoreTripActivityPreview.self) { context in
    StoreTripActivityContentView(context: context)
}

@available(iOS 17.0, *)
#Preview("Focus Session", as: .content, using: FocusSessionActivityPreview.self) { context in
    FocusSessionActivityContentView(context: context)
}
#endif
