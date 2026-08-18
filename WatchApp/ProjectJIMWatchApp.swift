import SwiftUI

@main
struct ProjectJIMWatchApp: App {
    @StateObject private var workout = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(workout)
        }
    }
}
