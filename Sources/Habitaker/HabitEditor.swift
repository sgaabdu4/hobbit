import SwiftUI

enum HobbitStyle {
    static let ink = adaptive(0x29342b, 0xf6f3e9)
    static let orange = Color(red: 233 / 255, green: 105 / 255, blue: 57 / 255)
    static let cream = adaptive(0xfbf8f1, 0x252720)
    static let softGreen = adaptive(0xedf0df, 0x394332)
    static let panel = adaptive(0xfffefa, 0x34392d)
    static let line = adaptive(0xe3e4d8, 0x484e40)
    static let muted = adaptive(0x73786b, 0xb6bdad)
    static let selected = adaptive(0xffeadb, 0x563426)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct HobbitButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(HobbitFont.body(15, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 17)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).tint(HobbitStyle.orange).foregroundStyle(Color.white)
    }
}

struct HabitEditor: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    var editing = false
    var adding = false
    var onSaved: () -> Void = {}
    @State private var habit = ""
    @State private var mode = "Gentle"
    @State private var time = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var reviewing = false
    @State private var confirmUnhinged = false
    @State private var attemptedSave = false
    @FocusState private var focused: Bool

    private var valid: Bool { !habit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && habit.count <= 140 }
    private var scheduleTimeZone: TimeZone {
        if !adding, let zone = calls.record?.timeZone, let saved = TimeZone(identifier: zone) { return saved }
        return .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if reviewing && !editing { Button("Back") { reviewing = false } }
            Text(adding ? "Add habit" : editing ? "Edit habit" : reviewing ? "Set your call" : "Choose a habit")
                .font(HobbitFont.title(28)).tracking(-1)
            if !reviewing && !editing {
                if !focused {
                PetView(pets: pets, expression: "thinking").frame(height: 120)
                if calls.checkingHabit { ProgressView("Checking your habit...") }
                else {
                    Button { Task { await calls.beginOnboarding() } } label: {
                        Label("Tell my pet", systemImage: "waveform").font(HobbitFont.body(15, weight: .bold)).frame(maxWidth: .infinity).padding(18)
                            .foregroundStyle(HobbitStyle.cream).background(HobbitStyle.ink, in: RoundedRectangle(cornerRadius: 20))
                    }.disabled(calls.actionBusy || !calls.ready)
                }
                }
                TextField("e.g. Stretch for two minutes", text: $habit, axis: .vertical)
                    .lineLimit(2)
                    .font(HobbitFont.body(18, weight: .semibold)).padding(20).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 20))
                    .focused($focused).accessibilityIdentifier("habit-input")
                if habit.count > 140 { Text("Keep it under 140 characters.").font(HobbitFont.body(14)).foregroundStyle(.red) }
                if focused { Button("Done typing") { focused = false }.frame(minHeight: 44) }
                if habit.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(["Stretch for two minutes", "Read one page", "Do ten squats"], id: \.self) { example in
                            Button { habit = example; focused = false } label: {
                                HStack { Text(example); Spacer(); Image(systemName: "arrow.up.left") }
                                    .padding(12).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 14))
                            }.foregroundStyle(HobbitStyle.ink)
                        }
                    }
                }
                HobbitButton(title: "Continue") { focused = false; reviewing = true }.disabled(!valid)
                if !calls.message.isEmpty { Text(calls.message).font(HobbitFont.body(12)).foregroundStyle(HobbitStyle.muted) }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("e.g. Read one page", text: $habit, axis: .vertical).font(HobbitFont.body(18, weight: .bold)).lineLimit(2).focused($focused).accessibilityIdentifier("habit-input")
                    if !focused {
                    Divider()
                    DatePicker("Call me every day", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact).font(HobbitFont.body(13, weight: .semibold))
                        .environment(\.timeZone, scheduleTimeZone)
                    Text(scheduleTimeZone.identifier.replacingOccurrences(of: "_", with: " "))
                        .font(HobbitFont.body(12)).foregroundStyle(HobbitStyle.muted)
                    if calls.draftDefaultTime { Text("I suggested this time. Change it if another time suits you.").font(HobbitFont.body(12)) }
                    }
                }.padding(18).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 24))
                if !focused {
                Text("How much of a push?").font(HobbitFont.body(18, weight: .bold))
                VStack(spacing: 8) {
                    modeRow("Gentle", detail: "A kind nudge. You've got this.", icon: "leaf")
                    modeRow("Aggressive", detail: "Less chat. More doing.", icon: "bolt")
                    modeRow("Unhinged", detail: "A tiny drill sergeant. Loud. Sweary.", icon: "flame")
                }
                }
                if attemptedSave || !calls.ready || !calls.pushReady {
                    Text(calls.message).font(HobbitFont.body(12)).foregroundStyle(HobbitStyle.muted).lineLimit(3)
                    if !calls.ready || !calls.pushReady {
                        Button("Retry connection") { Task { await calls.refresh() } }
                    }
                }
                Spacer(minLength: 0)
                HobbitButton(title: calls.saving ? "Saving your call..." : adding ? "Add habit" : editing ? "Save changes" : "Set my daily call") {
                    attemptedSave = true
                    focused = false
                    Task {
                        if await calls.savePlan(habit: habit, mode: mode, time: time, paused: adding ? false : calls.record?.paused ?? false, adding: adding, timeZone: scheduleTimeZone) { onSaved() }
                    }
                }.disabled(!valid || calls.saving || !calls.ready || !calls.pushReady)
            }
        }
        .foregroundStyle(HobbitStyle.ink)
        .onAppear {
            if !adding, let record = calls.record {
                habit = record.habit
                mode = record.mode
                time = record.calendar.date(bySettingHour: record.hour, minute: record.minute, second: 0, of: Date()) ?? Date()
            } else {
                mode = "Gentle"
                if adding {
                    let last = calls.records.map { $0.hour * 60 + $0.minute }.max() ?? 840
                    let next = (last + 30) % 1440
                    time = Calendar.current.date(bySettingHour: next / 60, minute: next % 60, second: 0, of: Date()) ?? Date()
                } else { applyDraft() }
            }
        }
        .onChange(of: calls.draftHabit) { _, _ in applyDraft() }
        .alert("Turn on Unhinged?", isPresented: $confirmUnhinged) {
            Button("Keep current mode", role: .cancel) {}
            Button("Use Unhinged") { mode = "Unhinged" }
        } message: { Text("Loud drill-sergeant commands, comic roasts and strong swearing. You can end any call instantly.") }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
    }

    private func applyDraft() {
        guard let draft = calls.draftHabit else { return }
        habit = draft
        time = Calendar.current.date(bySettingHour: calls.draftHour, minute: calls.draftMinute, second: 0, of: Date()) ?? Date()
        reviewing = true
    }

    private func modeRow(_ value: String, detail: String, icon: String) -> some View {
        Button {
            if value == "Unhinged" && mode != value { confirmUnhinged = true }
            else { mode = value }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(HobbitFont.body(17)).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value).font(HobbitFont.body(15, weight: .bold))
                    Text(detail).font(HobbitFont.body(12)).opacity(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: mode == value ? "checkmark.circle.fill" : "circle").font(HobbitFont.body(17))
            }.padding(14).foregroundStyle(HobbitStyle.ink)
                .background(mode == value ? HobbitStyle.selected : HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(mode == value ? HobbitStyle.orange : HobbitStyle.line, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(mode == value ? [.isSelected] : []).accessibilityIdentifier("mode-" + value.lowercased())
    }
}
