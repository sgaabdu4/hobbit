import SwiftUI

enum HobbitTab: String, CaseIterable {
    case today = "Today", habits = "Habits", settings = "Settings"
    var icon: String {
        switch self { case .today: return "sun.max"; case .habits: return "checklist"; case .settings: return "slider.horizontal.3" }
    }
}

struct HobbitTabBar: View {
    @Binding var selected: HobbitTab
    var body: some View {
        HStack(spacing: 8) {
            ForEach(HobbitTab.allCases, id: \.self) { tab in
                Button { selected = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 20, weight: .medium))
                        Text(tab.rawValue).font(HobbitFont.body(11, weight: .semibold))
                    }.frame(maxWidth: .infinity).frame(height: 54)
                        .foregroundStyle(selected == tab ? HobbitStyle.orange : HobbitStyle.muted)
                        .background(selected == tab ? HobbitStyle.orange.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("tab-" + tab.rawValue.lowercased())
                    .accessibilityAddTraits(selected == tab ? .isSelected : [])
            }
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
            .background(HobbitStyle.cream)
            .overlay(alignment: .top) { Rectangle().fill(HobbitStyle.line).frame(height: 1) }
    }
}

struct CompactTodayView: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    var edit: () -> Void
    var add: () -> Void

    private var index: Int { calls.records.firstIndex { $0.id == calls.record?.id } ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today").font(HobbitFont.title(30)).tracking(-1)
                        Text("\(calls.records.filter { $0.isCompleted() }.count) of \(calls.records.count) done today")
                            .font(HobbitFont.body(13)).foregroundStyle(HobbitStyle.muted)
                    }
                    Spacer()
                    Button(action: add) { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44).background(HobbitStyle.panel, in: Circle()) }
                        .accessibilityLabel("Add habit").accessibilityIdentifier("today-add-habit")
                }
                if calls.records.count > 1 { HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 36) }
                        .disabled(index == 0 || calls.scheduledID != nil).accessibilityLabel("Previous habit")
                    Spacer()
                    Text("Habit \(index + 1) of \(calls.records.count)").font(HobbitFont.body(12, weight: .semibold)).foregroundStyle(HobbitStyle.muted)
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 36) }
                        .disabled(index + 1 >= calls.records.count || calls.scheduledID != nil).accessibilityLabel("Next habit")
                } }
                PetView(pets: pets, expression: calls.completed ? "happy" : "attentive", mode: calls.mode)
                    .frame(height: max(70, min(210, geometry.size.height - (calls.records.count > 1 ? 440 : 390) - (calls.attentionMessage.isEmpty ? 0 : 65))))
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(calls.record?.paused == true ? "CALLS PAUSED" : calls.completed ? "DONE TODAY" : calls.mode.uppercased())
                            .font(HobbitFont.label(10)).tracking(1).foregroundStyle(HobbitStyle.muted)
                        Spacer()
                        Button("Edit", action: edit).font(HobbitFont.body(13, weight: .semibold)).accessibilityIdentifier("edit-habit")
                    }
                    Text(calls.habit).font(HobbitFont.title(22)).tracking(-0.5).lineLimit(2)
                    if let date = calls.nextCall {
                        Label("Next call \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))", systemImage: "phone.arrow.down.left")
                            .font(HobbitFont.body(13)).foregroundStyle(HobbitStyle.muted)
                    } else if calls.record?.paused == true {
                        Text("Calls paused. Change this in Habits.").font(HobbitFont.body(13)).foregroundStyle(HobbitStyle.muted)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(HobbitStyle.line, lineWidth: 1))
                Spacer(minLength: 0)
                if !calls.attentionMessage.isEmpty {
                    Text(calls.attentionMessage).font(HobbitFont.body(13)).foregroundStyle(HobbitStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("call-feedback")
                }
                if calls.scheduledID != nil {
                    Text("Your pet will ring shortly.").font(HobbitFont.body(14))
                    HobbitButton(title: "Cancel call") { Task { await calls.cancelScheduled() } }
                } else if calls.completed {
                    Label("\(calls.record?.streak() ?? 1) day streak", systemImage: "flame.fill").font(HobbitFont.body(16, weight: .bold))
                        .frame(maxWidth: .infinity)
                    Button("Undo today's completion") { calls.markCompleted(false) }.font(HobbitFont.body(14)).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    HobbitButton(title: "Talk to my pet") { Task { await calls.callNow() } }
                        .disabled(calls.actionBusy || !calls.ready).accessibilityIdentifier("talk-to-pet")
                    Button("I did it") { calls.markCompleted(true) }.font(HobbitFont.body(15, weight: .bold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                if !calls.ready {
                    Button("Reconnect to enable calls") { Task { await calls.refresh() } }
                        .font(HobbitFont.body(12)).frame(maxWidth: .infinity, minHeight: 36)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func move(_ offset: Int) {
        let next = index + offset
        guard calls.records.indices.contains(next) else { return }
        calls.selectHabit(calls.records[next].id)
    }
}

struct HabitLibraryView: View {
    @ObservedObject var calls: CallCoordinator
    var add: () -> Void
    var edit: (String) -> Void
    var open: (String) -> Void
    @State private var page = 0

    var body: some View {
        GeometryReader { geometry in
            let count = geometry.size.height < 560 ? 3 : 4
            let pages = max(1, (calls.records.count + count - 1) / count)
            let current = min(page, pages - 1)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Habits").font(HobbitFont.title(30)).tracking(-1)
                    Spacer()
                    Button(action: add) { Label("Add", systemImage: "plus").font(HobbitFont.body(14, weight: .bold)).padding(12).background(HobbitStyle.orange, in: Capsule()).foregroundStyle(.white) }
                        .accessibilityIdentifier("add-habit")
                }
                ForEach(Array(calls.records.dropFirst(current * count).prefix(count))) { record in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { open(record.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: record.isCompleted() ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(record.isCompleted() ? HobbitStyle.orange : HobbitStyle.muted).font(.system(size: 23))
                                Text(record.habit).font(HobbitFont.body(16, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12))
                            }.frame(minHeight: 40).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("open-habit-" + record.id)
                        HStack {
                            Text(record.paused ? "Paused" : String(format: "%02d:%02d daily", record.hour, record.minute))
                            Text("/ " + record.mode)
                            Spacer()
                            Button("Edit") { edit(record.id) }.fontWeight(.bold).accessibilityIdentifier("edit-habit-" + record.id)
                        }.font(HobbitFont.body(12)).foregroundStyle(HobbitStyle.muted)
                    }.padding(18).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HobbitStyle.line, lineWidth: 1))
                }
                Spacer(minLength: 0)
                if pages > 1 { HStack {
                    Button("Previous") { page = current - 1 }.disabled(current == 0).opacity(current == 0 ? 0.35 : 1).frame(minHeight: 44)
                    Spacer()
                    Text("\(current + 1) / \(pages)").foregroundStyle(HobbitStyle.muted)
                    Spacer()
                    Button("Next") { page = current + 1 }.disabled(current + 1 >= pages).opacity(current + 1 >= pages ? 0.35 : 1).frame(minHeight: 44)
                }.font(HobbitFont.body(13, weight: .semibold)) }
            }.disabled(calls.saving || calls.scheduledID != nil)
        }
    }
}

struct HobbitSettingsView: View {
    @ObservedObject var calls: CallCoordinator
    var changePet: () -> Void
    @AppStorage("quietPetMotion") private var quietMotion = false
    @State private var feedback = ""
    @Environment(\.openURL) private var openURL
    private var allPaused: Bool { !calls.records.isEmpty && calls.records.allSatisfy(\.paused) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(HobbitFont.title(30)).tracking(-1)
            Label("Connected with ChatGPT", systemImage: "checkmark.shield")
                .font(HobbitFont.body(13)).foregroundStyle(HobbitStyle.muted)
            VStack(spacing: 0) {
                settingsButton("Change pet", icon: "pawprint", action: changePet)
                Divider()
                Toggle(isOn: $quietMotion) {
                    Label("Calmer pet movement", systemImage: "leaf")
                }.font(HobbitFont.body(14)).padding(16).tint(HobbitStyle.orange)
                Divider()
                settingsButton("Microphone & permissions", icon: "mic") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }.background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 22))
            VStack(spacing: 0) {
                settingsButton(allPaused ? "Resume all daily calls" : "Pause all daily calls", icon: allPaused ? "play.circle" : "pause.circle") {
                    Task { await calls.pauseAll(!allPaused); feedback = calls.message }
                }.disabled(calls.saving || calls.records.isEmpty || calls.scheduledID != nil)
                Divider()
                settingsButton("Check connection", icon: "wifi") { Task { await calls.refresh(); feedback = calls.ready && calls.pushReady ? "Connected. Calls are ready." : calls.message } }
            }.background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 22))
            if !feedback.isEmpty || !calls.ready {
                Text(calls.ready ? feedback : calls.message).font(HobbitFont.body(13)).foregroundStyle(HobbitStyle.muted).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
    }

    private func settingsButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(HobbitStyle.orange)
                Text(title).font(HobbitFont.body(14, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(HobbitStyle.muted)
            }.padding(16).frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
