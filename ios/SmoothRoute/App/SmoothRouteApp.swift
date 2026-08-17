import SwiftUI

@main
struct SmoothRouteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = RideRecorder()

    var body: some Scene {
        WindowGroup {
            ContentView(recorder: recorder)
                .onChange(of: scenePhase) { _, newPhase in
                    recorder.handleScenePhase(newPhase)
                }
        }
    }
}
