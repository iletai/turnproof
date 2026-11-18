import SwiftUI

struct ContentView: View {
    var body: some View {
        PropertiesListView()
    }
}

#Preview {
    ContentView()
        .environment(AppModel.shared)
        .environment(AppRouter())
}
