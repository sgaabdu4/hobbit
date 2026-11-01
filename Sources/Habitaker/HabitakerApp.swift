import SwiftUI

@main
struct HabitakerApp: App {
    @StateObject private var auth = AuthCoordinator()
    @StateObject private var calls = CallCoordinator.shared
    @StateObject private var pets = PetStore()
    @Environment(\.scenePhase) private var scenePhase
    init() { DesignDiagnostics.record() }
    var body: some Scene {
        WindowGroup {
            if auth.verified {
                HabitFlow(calls: calls, pets: pets).preferredColorScheme(.dark)
            } else {
                WelcomeView(auth: auth, pets: pets).preferredColorScheme(.dark)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await auth.refreshIfNeeded() } }
        }
    }
}
