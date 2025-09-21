import SwiftUI

struct ExpensesView: View {
    var body: some View {
        NavigationStack {
            Text("Expenses")
                .navigationTitle("Expenses")
        }
    }
}

#Preview {
    ExpensesView()
}
