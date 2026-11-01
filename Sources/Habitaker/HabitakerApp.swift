import SwiftUI

@main
struct HabitakerApp: App {
    @StateObject private var auth = AuthCoordinator()
    @StateObject private var calls = CallCoordinator.shared
    @StateObject private var pets = PetStore()
    var body: some Scene {
        WindowGroup {
            if auth.verified {
                HabitFlow(calls: calls, pets: pets)
            } else {
            VStack(alignment: .leading, spacing: 28) {
                Text("hobbit.").font(.title2.bold())
                Spacer()
                Image(systemName: auth.verified ? "checkmark.shield.fill" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 62)).foregroundStyle(Color.orange)
                Text(auth.verified ? "You're signed in." : "Your pet.\nYour daily push.")
                    .font(.largeTitle.bold())
                Text(auth.message).font(.body).accessibilityIdentifier("auth-status")
                if auth.busy { ProgressView().accessibilityLabel("Sign-in in progress") }
                if auth.verified {
                    Label(auth.planEnabled ? "ChatGPT plan permission granted" : "ChatGPT plan permission not granted",
                          systemImage: auth.planEnabled ? "checkmark.circle" : "info.circle")
                    Label("A new pet for Hobbit", systemImage: "pawprint")
                }
                Spacer()
                Button("Continue with ChatGPT", action: auth.signIn)
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(auth.busy || auth.verified)
                Text("Sign in to meet your AI habit companion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(28)
            }
        }
    }
}
