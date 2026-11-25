import SwiftUI
import PiHoleKit

@main
struct PiHoleControlsiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                Text("Pi-hole Controls")
                    .font(.title)
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Pi-hole")
        }
    }
}
