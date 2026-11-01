import SwiftUI

struct PetView: View {
    @ObservedObject var pets: PetStore
    var expression = "attentive"
    var audioLevel = 0.0
    var previewing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: reduceMotion)) { time in
            let phase = time.date.timeIntervalSinceReferenceDate
            Group {
                if let image = pets.frame(expression: expression, speaking: audioLevel > 0.008, previewing: previewing) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView("Your pet is loading")
                }
            }
            .offset(y: reduceMotion ? 0 : sin(phase * 2) * 4)
            .rotationEffect(.degrees(reduceMotion || expression != "happy" ? 0 : sin(phase * 5) * 5))
            .accessibilityLabel(audioLevel > 0.008 ? "Your pet is speaking" : "Your pet is " + expression)
        }
    }
}

struct HabitFlow: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    @State private var creating = false
    @State private var description = "A tiny teal owl with a mischievous smile"
    @State private var confirmUnhinged = false
    @State private var ranVoiceCheck = false
    @Environment(\.scenePhase) private var scenePhase
    private let ink = Color(red: 0.10, green: 0.24, blue: 0.20)
    private let accent = Color(red: 0.88, green: 0.32, blue: 0.16)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("hobbit.").font(.system(size: 25, weight: .black, design: .rounded))
                    Spacer()
                    if pets.chosen { Text(calls.active ? "AI voice call" : "Today").font(.subheadline).foregroundStyle(.secondary) }
                }
                if !pets.chosen { onboarding }
                else if calls.active || calls.connecting { callScreen }
                else { today }
            }
            .padding(26)
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.98, green: 0.97, blue: 0.93).ignoresSafeArea())
        .tint(accent)
        .task {
            await calls.refresh()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--voice-check"), !ranVoiceCheck {
                ranVoiceCheck = true
                await calls.callNow()
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { calls.end() }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await calls.refresh() } }
        }
        .alert("Turn on Unhinged?", isPresented: $confirmUnhinged) {
            Button("Keep current mode", role: .cancel) {}
            Button("Use Unhinged") { calls.mode = "Unhinged"; calls.saveHabit() }
        } message: { Text("Fierce comic pressure, sharp roasts and strong swearing. You can end any call instantly.") }
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(creating ? "Make it yours." : "Meet your daily push.").font(.system(size: 36, weight: .bold, design: .rounded))
            PetView(pets: pets, previewing: pets.preview != nil && creating).frame(height: 260)
            if creating {
                TextField("Describe your pet", text: $description, axis: .vertical)
                    .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(pets.busy)
                if !pets.message.isEmpty { Text(pets.message).font(.callout).accessibilityAddTraits(.updatesFrequently) }
                if pets.busy { ProgressView().frame(maxWidth: .infinity) }
                if pets.preview != nil { primary("Use this pet") { pets.chooseCustom() } }
                else { primary("Create my pet") { Task { await pets.generate(description) } }.disabled(pets.busy || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.count > 180) }
                Button("Use Pip instead") { pets.chooseDefault() }.frame(maxWidth: .infinity).disabled(pets.busy)
            } else {
                Text("Pip will call, listen and cheer you on.").font(.title3)
                primary("Use Pip") { pets.chooseDefault() }
                Button("Create my pet") { creating = true }.font(.headline).frame(maxWidth: .infinity).padding(8)
            }
        }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(calls.completed ? "You showed up." : "Small step.\nBig smug energy.").font(.system(size: 36, weight: .bold, design: .rounded))
            PetView(pets: pets, expression: calls.completed ? "happy" : "attentive").frame(height: 240)
            if calls.completed {
                Text(calls.habit).font(.title3.bold())
                Text("Done today. Saved on this iPhone.")
                Button("Undo completion") { calls.markCompleted(false) }
            } else {
                TextField("Your one habit", text: $calls.habit, axis: .vertical)
                    .font(.title3.weight(.semibold)).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .onSubmit { calls.saveHabit() }
                    .disabled(calls.scheduledID != nil)
                HStack(spacing: 8) {
                    ForEach(["Gentle", "Aggressive", "Unhinged"], id: \.self) { mode in
                        Button {
                            if mode == "Unhinged" && calls.mode != mode { confirmUnhinged = true }
                            else { calls.mode = mode; calls.saveHabit() }
                        } label: {
                            Text(mode).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .foregroundStyle(calls.mode == mode ? Color.white : ink)
                                .background(calls.mode == mode ? ink : Color.white, in: Capsule())
                        }
                    }
                }
                .disabled(calls.scheduledID != nil)
                Text(calls.message).font(.callout).foregroundStyle(.secondary)
                primary("Talk to my pet") { Task { await calls.callNow() } }.disabled(calls.scheduledID != nil || !calls.ready || calls.habit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if calls.scheduledID != nil { Button("Cancel scheduled call") { Task { await calls.cancelScheduled() } }.frame(maxWidth: .infinity) }
                else { Button("Call me in 15 seconds") { Task { await calls.schedule() } }.frame(maxWidth: .infinity).disabled(!calls.pushReady || !calls.ready || calls.habit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                if !calls.ready || !calls.pushReady { Button("Retry connection") { Task { await calls.refresh() } }.frame(maxWidth: .infinity) }
            }
        }
    }

    private var callScreen: some View {
        VStack(spacing: 24) {
            Text(calls.connecting ? "Your pet is joining..." : calls.completed ? "You did it." : "I'm here. Let's do this.")
                .font(.system(size: 32, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
            PetView(pets: pets, expression: calls.expression, audioLevel: calls.audioLevel).frame(height: 330)
            Text(calls.habit).font(.title3.bold())
            Text(calls.message).font(.callout).multilineTextAlignment(.center)
            if calls.connecting { ProgressView() }
            HStack(spacing: 26) {
                Button { calls.toggleMute() } label: { Label(calls.muted ? "Unmute" : "Mute", systemImage: calls.muted ? "mic.slash.fill" : "mic.fill").padding(18).background(.white, in: Capsule()) }
                Button { calls.end() } label: { Label("End", systemImage: "phone.down.fill").padding(18).foregroundStyle(.white).background(Color.red, in: Capsule()) }
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 19) }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 20))
    }
}
