import SwiftUI

@main
struct ProjectJIMApp: App {
    @StateObject private var connectivity = PhoneConnectivityManager()
    @StateObject private var history = WorkoutHistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
                .environmentObject(history)
        }
    }
}
