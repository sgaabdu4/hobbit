import SwiftUI

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
    @State private var petKind = "Fox"
    @State private var petColour = "Orange"
    @State private var petDetails = ""
    @FocusState private var petDetailsFocused: Bool
    @State private var ranVoiceCheck = false
    @State private var editing = false
    @State private var adding = false
    @State private var tab = HobbitTab.today
    @State private var confirmHabitRemoval = false
    @State private var finalHabitRemoval = false
    @State private var changingPet = false
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
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    HobbitWordmark()
                    Spacer()
                }
                if calls.active || calls.connecting { callScreen }
                else if !pets.chosen || changingPet { onboarding }
                else if calls.record == nil { HabitEditor(calls: calls, pets: pets) }
                else if calls.showingCelebration { CelebrationView(calls: calls, pets: pets) }
                else {
                    switch tab {
                    case .today:
                        CompactTodayView(calls: calls, pets: pets, edit: { adding = false; editing = true }, add: addHabit)
                    case .habits:
                        HabitLibraryView(calls: calls, add: addHabit, edit: { id in
                            calls.selectHabit(id); adding = false; editing = true
                        }, open: { id in calls.selectHabit(id); tab = .today })
                    case .settings:
                        HobbitSettingsView(calls: calls, changePet: { creating = false; changingPet = true })
                    }
                }
                if !pets.chosen || changingPet { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pets.chosen && calls.record != nil && !calls.active && !calls.connecting && !changingPet {
                HobbitTabBar(selected: $tab)
            }
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
        .sheet(isPresented: $editing) {
            NavigationStack {
                VStack(spacing: 8) {
                    HabitEditor(calls: calls, pets: pets, editing: true, adding: adding, onSaved: { editing = false; tab = .today })
                    if !adding {
                        HStack {
                            Button(calls.record?.paused == true ? "Resume this call" : "Pause this call") { Task { await calls.togglePause() } }
                            Spacer()
                            Button("Delete habit", role: .destructive) { confirmHabitRemoval = true }.accessibilityIdentifier("delete-habit")
                        }.font(HobbitFont.body(13)).frame(minHeight: 44).disabled(calls.saving)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 8)
                    .background(HobbitStyle.cream)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false }.disabled(calls.saving) } }
                    .confirmationDialog("Delete this habit?", isPresented: $confirmHabitRemoval, titleVisibility: .visible) {
                        Button("Continue deleting", role: .destructive) { finalHabitRemoval = true }
                        Button("Keep habit", role: .cancel) {}
                    } message: { Text("Its daily call and saved progress will be removed.") }
                    .alert("Delete habit and progress?", isPresented: $finalHabitRemoval) {
                        Button("Keep habit", role: .cancel) {}
                        Button("Delete permanently", role: .destructive) {
                            guard let id = calls.record?.id else { return }
                            Task { if await calls.deleteHabit(id) { editing = false } }
                        }
                    } message: { Text("This cannot be undone. Your other habits will stay.") }
            }.interactiveDismissDisabled(calls.saving).presentationDetents([.large]).preferredColorScheme(.dark).tint(HobbitStyle.orange)
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
        .onChange(of: tab) { _, _ in calls.showingCelebration = false }
        .onChange(of: calls.connecting) { _, connecting in
            if connecting { editing = false }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in calls.checkDay() }
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(creating ? "Create your pet" : "Choose your pet").font(HobbitFont.title(30)).tracking(-1)
            if !creating || pets.preview != nil || pets.busy {
            PetView(pets: pets, audioLevel: previewLevel, previewing: pets.preview != nil && creating, mode: previewMode).frame(height: 180)
                .overlay(alignment: .topTrailing) {
                    if !creating {
                        Text("Excuses? Interesting.").font(HobbitFont.body(11, weight: .semibold)).padding(12)
                            .background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HobbitStyle.line, lineWidth: 1))
                            .rotationEffect(.degrees(7)).offset(y: 10)
                    }
                }
            }
            if pets.preview != nil && creating {
                Picker("Preview expression", selection: $previewMode) {
                    Text("Calm").tag("Gentle")
                    Text("Stern").tag("Aggressive")
                    Text("Angry").tag("Unhinged")
                }.pickerStyle(.segmented)
                Button(previewTalking ? "Stop preview" : "Preview talking") { previewTalking.toggle() }
                    .font(HobbitFont.body(13)).buttonStyle(.bordered)
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
                if pets.preview == nil && !pets.busy {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What kind of pet?").font(HobbitFont.body(17, weight: .bold))
                        Picker("Pet type", selection: $petKind) {
                            ForEach(["Fox", "Cat", "Owl", "Dragon"], id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.segmented)
                    }.padding(18).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Which colour?").font(HobbitFont.body(17, weight: .bold))
                        Picker("Pet colour", selection: $petColour) {
                            ForEach(["Orange", "Teal", "Purple"], id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.segmented)
                    }.padding(18).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 20))
                    TextField("Anything else? Optional", text: $petDetails, axis: .vertical)
                        .lineLimit(2).focused($petDetailsFocused).accessibilityIdentifier("pet-details")
                        .padding(18).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 18))
                    if petDetailsFocused { Button("Done typing") { petDetailsFocused = false }.frame(minHeight: 44) }
                    if petDetails.count > 100 { Text("Keep extra details under 100 characters.").font(HobbitFont.body(12)) }
                }
                if !pets.message.isEmpty { Text(pets.message).font(HobbitFont.body(14)).accessibilityAddTraits(.updatesFrequently) }
                if pets.busy { ProgressView().frame(maxWidth: .infinity) }
                if pets.preview != nil {
                    primary("Use this pet") {
                        if pets.custom != nil { confirmReplacement = true }
                        else { saveCustomPet() }
                    }
                }
                else {
                    primary(pets.busy ? "Creating your pet..." : "Create my pet") {
                        petDetailsFocused = false
                        let description = "A tiny " + petColour.lowercased() + " " + petKind.lowercased() + ". " + petDetails.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await pets.generate(description) }
                    }.disabled(pets.busy || petDetails.count > 100)
                }
                if pets.preview != nil { Button("Change my answers") { pets.preview = nil; pets.message = ""; previewTalking = false }.frame(maxWidth: .infinity, minHeight: 44) }
                Button("Use Pip instead") { pets.chooseDefault(); changingPet = false }.frame(maxWidth: .infinity).disabled(pets.busy)
            } else {
                Text("Pip").font(HobbitFont.body(14, weight: .medium)).foregroundStyle(HobbitStyle.muted).frame(maxWidth: .infinity)
                primary("Use Pip") { pets.chooseDefault(); changingPet = false }
                if pets.custom != nil {
                    Button("Use my saved pet") { pets.chooseSavedCustom(); changingPet = false }
                        .font(HobbitFont.body(14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 40)
                }
                Button("Create my pet") { pets.preview = nil; pets.message = ""; creating = true }.font(HobbitFont.body(15, weight: .bold)).frame(maxWidth: .infinity).padding(8)
                if !pets.message.isEmpty { Text(pets.message).font(HobbitFont.body(14)) }
            }
            if changingPet { Button("Keep my current pet") { changingPet = false }.frame(maxWidth: .infinity).disabled(pets.busy) }
        }
    }

    private var callScreen: some View {
        VStack(spacing: 16) {
            Text(calls.ringing || calls.connecting ? "Calling Pip" : calls.completed ? "Habit complete" : "Pip")
                .font(HobbitFont.title(34)).tracking(-1.3).frame(maxWidth: .infinity)
            PetView(pets: pets, expression: calls.expression, audioLevel: calls.audioLevel, mode: calls.onboardingVoice ? "Gentle" : calls.mode).frame(maxHeight: .infinity)
                .frame(minHeight: 100)
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
            } else if !calls.connecting && !calls.ringing && !calls.ending && !calls.completed { primary("I did it") { calls.markCompleted(true); calls.sayGoodbyeAndEnd() } }
            HStack(spacing: 26) {
                Button { calls.toggleMute() } label: { Label(calls.muted ? "Unmute" : "Mute", systemImage: calls.muted ? "mic.slash.fill" : "mic.fill").padding(18).background(HobbitStyle.panel, in: Capsule()) }.disabled(calls.ending)
                Button { calls.end() } label: { Label(calls.ending ? "End now" : "End", systemImage: "phone.down.fill").padding(18).foregroundStyle(.white).background(Color.red, in: Capsule()) }
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        HobbitButton(title: title, action: action)
    }

    private func saveCustomPet() {
        if pets.chooseCustom() { changingPet = false }
    }

    private func addHabit() {
        calls.draftHabit = nil
        calls.draftDefaultTime = false
        calls.message = ""
        adding = true
        editing = true
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
