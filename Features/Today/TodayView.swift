import SwiftUI

struct TodayView: View {
    var body: some View {
        NavigationStack {
            Text("Today Overview")
                .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
}
