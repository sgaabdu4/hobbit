import SwiftUI
import UniformTypeIdentifiers

struct PetView: View {
    @ObservedObject var pets: PetStore
    var expression = "attentive"
    var audioLevel = 0.0
    var previewing = false
    var mode = "Gentle"
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(HobbitStyle.softGreen).frame(width: size * 0.88, height: size * 0.88)
                AnimatedPetView(pets: pets, expression: expression, audioLevel: audioLevel, mode: mode, previewing: previewing)
                    .frame(width: size, height: size)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct HabitFlow: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    @State private var creating = false
    @State private var description = "A tiny teal owl with a mischievous smile"
    @State private var ranVoiceCheck = false
    @State private var editing = false
    @State private var changingPet = false
    @State private var importing = false
    @State private var previewMode = "Gentle"
    @State private var previewTalking = false
    @State private var previewLevel = 0.0
    @State private var confirmReplacement = false
    @State private var confirmRemoval = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    private let ink = HobbitStyle.ink
    private let accent = HobbitStyle.orange
    private var screenKey: String {
        if calls.active || calls.connecting { return "call" }
        if !pets.chosen || changingPet { return creating ? "create-pet" : "choose-pet" }
        if calls.record == nil { return "habit-setup" }
        return calls.showingCelebration ? "celebration" : "today"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 6) {
                    HobbitWordmark()
                    Spacer()
                    if pets.chosen { Text(calls.active ? "YOU + PIP" : "YOUR TINY COACH").font(HobbitFont.label(9)).tracking(1.5).foregroundStyle(HobbitStyle.muted) }
                }
                if calls.active || calls.connecting { callScreen }
                else if !pets.chosen || changingPet { onboarding }
                else if calls.record == nil { HabitEditor(calls: calls, pets: pets) }
                else if calls.showingCelebration { CelebrationView(calls: calls, pets: pets) }
                else { TodayView(calls: calls, pets: pets, edit: { editing = true }, changePet: { creating = false; changingPet = true }) }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 28)
        }
        .id(screenKey)
        .foregroundStyle(ink)
        .font(HobbitFont.body())
        .background((calls.active || calls.connecting ? Color(red: 23 / 255, green: 39 / 255, blue: 30 / 255) : HobbitStyle.cream).ignoresSafeArea())
        .environment(\.colorScheme, calls.active || calls.connecting ? .dark : colorScheme)
        .tint(accent)
        .confirmationDialog("Replace your saved custom pet?", isPresented: $confirmReplacement, titleVisibility: .visible) {
            Button("Continue replacing") { confirmRemoval = true }
            Button("Keep my pet", role: .cancel) {}
        } message: { Text("Your new pet will take its place. Pip is always available.") }
        .alert("Remove the old custom pet?", isPresented: $confirmRemoval) {
            Button("Keep my pet", role: .cancel) {}
            Button("Replace pet", role: .destructive) { saveCustomPet() }
        } message: { Text("The old sprite will be removed from this phone. This cannot be undone.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw AuthFailure.invalid("Choose a PNG smaller than 20 MB.") }
                try pets.importSheet(data: Data(contentsOf: url), columns: 4)
                creating = true
            } catch { pets.message = error.localizedDescription }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ScrollView { HabitEditor(calls: calls, pets: pets, editing: true, onSaved: { editing = false }).padding(26) }
                    .background(HobbitStyle.cream)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false }.disabled(calls.saving) } }
            }.interactiveDismissDisabled(calls.saving)
        }
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
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in calls.checkDay() }
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 20) {
            if creating { Text("Make it yours.").font(HobbitFont.title()).tracking(-1.3) }
            else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Small pet.").font(HobbitFont.title()).tracking(-1.3)
                    Text("Big get-up energy.").font(HobbitFont.title()).tracking(-1.3).foregroundStyle(accent)
                }.accessibilityElement(children: .combine).accessibilityLabel("Meet your daily push.")
            }
            PetView(pets: pets, audioLevel: previewLevel, previewing: pets.preview != nil && creating, mode: previewMode).frame(height: 215)
                .overlay(alignment: .topTrailing) {
                    if !creating {
                        Text("Excuses? Interesting.").font(HobbitFont.body(11, weight: .semibold)).padding(12)
                            .background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HobbitStyle.line, lineWidth: 1))
                            .rotationEffect(.degrees(7)).offset(y: 10)
                    }
                }
            if pets.preview != nil && creating {
                Picker("Preview expression", selection: $previewMode) {
                    Text("Calm").tag("Gentle")
                    Text("Stern").tag("Aggressive")
                    Text("Angry").tag("Unhinged")
                }.pickerStyle(.segmented)
                Toggle("Preview talking", isOn: $previewTalking).font(HobbitFont.body(13))
                    .task(id: previewTalking) {
                        while previewTalking && !Task.isCancelled {
                            previewLevel = 0.07
                            try? await Task.sleep(for: .milliseconds(180))
                            previewLevel = 0.012
                            try? await Task.sleep(for: .milliseconds(140))
                            previewLevel = 0
                            try? await Task.sleep(for: .milliseconds(220))
                        }
                        previewLevel = 0
                    }
            }
            if creating {
                TextField("Describe your pet", text: $description, axis: .vertical)
                    .padding(18).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(pets.busy)
                if !pets.message.isEmpty { Text(pets.message).font(HobbitFont.body(14)).accessibilityAddTraits(.updatesFrequently) }
                if pets.busy { ProgressView().frame(maxWidth: .infinity) }
                if pets.preview != nil {
                    primary("Use this pet") {
                        if pets.custom != nil { confirmReplacement = true }
                        else { saveCustomPet() }
                    }
                }
                else { primary("Create my pet") { Task { await pets.generate(description) } }.disabled(pets.busy || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.count > 180) }
                Button("Use Pip instead") { pets.chooseDefault(); changingPet = false }.frame(maxWidth: .infinity).disabled(pets.busy)
            } else {
                Text("Pip / your tiny coach").font(HobbitFont.body(14, weight: .medium)).foregroundStyle(HobbitStyle.muted).frame(maxWidth: .infinity)
                primary("Use Pip") { pets.chooseDefault(); changingPet = false }
                Button("Create my pet") { pets.preview = nil; creating = true }.font(HobbitFont.body(15, weight: .bold)).frame(maxWidth: .infinity).padding(8)
                Button("Import a sprite sheet") { importing = true }.font(HobbitFont.body(13)).frame(maxWidth: .infinity)
                Text("Import a square PNG with a 4 by 4 expression grid.").font(HobbitFont.body(11)).foregroundStyle(HobbitStyle.muted).frame(maxWidth: .infinity)
                if !pets.message.isEmpty { Text(pets.message).font(HobbitFont.body(14)) }
            }
            if changingPet { Button("Keep my current pet") { changingPet = false }.frame(maxWidth: .infinity).disabled(pets.busy) }
        }
    }

    private var callScreen: some View {
        VStack(spacing: 24) {
            Text(calls.ringing || calls.connecting ? "Calling Pip." : calls.completed ? "You did it." : "A little push.")
                .font(HobbitFont.title(34)).tracking(-1.3).frame(maxWidth: .infinity)
            PetView(pets: pets, expression: calls.expression, audioLevel: calls.audioLevel, mode: calls.onboardingVoice ? "Gentle" : calls.mode).frame(height: 230)
                .overlay { if calls.ringing || calls.connecting { RingingHalo() } }
            Text(calls.onboardingVoice ? "Tell me one habit and a call time." : calls.habit).font(HobbitFont.body(14)).foregroundStyle(HobbitStyle.muted)
            Group {
                if calls.ringing || calls.connecting {
                    Label("Ringing...", systemImage: "phone.arrow.up.right").accessibilityIdentifier("ringing-status")
                } else {
                    Text(calls.caption.isEmpty ? calls.message : String(calls.caption.suffix(180)))
                }
            }.font(HobbitFont.body(18, weight: .medium)).multilineTextAlignment(.center).lineSpacing(3)
                .lineLimit(4).frame(maxWidth: .infinity, minHeight: 95, maxHeight: 95)
            if calls.onboardingVoice {
                primary("Check my habit") { Task { await calls.checkSpokenHabit() } }.disabled(calls.connecting || calls.checkingHabit)
            } else if !calls.connecting && !calls.ringing && !calls.completed { primary("I did it") { calls.markCompleted(true); calls.end() } }
            HStack(spacing: 26) {
                Button { calls.toggleMute() } label: { Label(calls.muted ? "Unmute" : "Mute", systemImage: calls.muted ? "mic.slash.fill" : "mic.fill").padding(18).background(HobbitStyle.panel, in: Capsule()) }
                Button { calls.end() } label: { Label("End", systemImage: "phone.down.fill").padding(18).foregroundStyle(.white).background(Color.red, in: Capsule()) }
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        HobbitButton(title: title, action: action)
    }

    private func saveCustomPet() {
        if pets.chooseCustom() { changingPet = false }
    }
}

private struct RingingHalo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            ZStack {
                ForEach(0..<2) { index in
                    let progress = (phase + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle().stroke(HobbitStyle.orange.opacity(reduceMotion ? 0.25 : (1 - progress) * 0.55), lineWidth: 2)
                        .frame(width: 200, height: 200).scaleEffect(reduceMotion ? 1.1 : 1 + progress * 0.3)
                }
                Image(systemName: "phone.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .padding(15).background(HobbitStyle.orange, in: Circle())
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(phase * .pi * 24) * 12))
                    .offset(x: 82, y: 76)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
