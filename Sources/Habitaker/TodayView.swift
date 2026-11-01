import SwiftUI

struct TodayView: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    var edit: () -> Void
    var changePet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()).font(HobbitFont.label(10)).tracking(1.3).foregroundStyle(HobbitStyle.muted)
                Text(calls.completed ? "Look at you go." : "Today, we show up.")
                    .font(HobbitFont.title(30)).tracking(-1.3)
                Text(calls.completed ? "One small promise, kept." : "Pip's here. Your only job is to start.")
                    .font(HobbitFont.body(14)).foregroundStyle(HobbitStyle.muted)
            }
            HabitWeek(record: calls.record)
            ZStack(alignment: .bottom) {
                PetView(pets: pets, expression: calls.completed ? "happy" : "attentive", mode: calls.mode).frame(height: 190)
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(calls.completed ? "DONE TODAY" : calls.record?.paused == true ? "CALLS PAUSED" : "YOUR DAILY HABIT", systemImage: calls.completed ? "checkmark.circle.fill" : "clock")
                        .font(HobbitFont.label(10)).tracking(1)
                    Spacer()
                    Text(calls.mode).font(HobbitFont.body(12, weight: .semibold))
                }.foregroundStyle(HobbitStyle.muted)
                Text(calls.habit).font(HobbitFont.title(21)).tracking(-0.6)
                if let date = calls.nextCall {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.arrow.down.left")
                        Text("Next call \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    }.font(HobbitFont.body(13))
                } else if calls.record?.paused == true {
                    Text("No daily calls until you resume.").font(HobbitFont.body(13))
                }
                Divider()
                HStack {
                    Button("Edit habit", action: edit).accessibilityIdentifier("edit-habit")
                    Spacer()
                    Button(calls.record?.paused == true ? "Resume calls" : "Pause calls") { Task { await calls.togglePause() } }
                }.font(HobbitFont.body(13, weight: .semibold)).disabled(calls.saving || calls.scheduledID != nil)
            }.padding(18).background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(HobbitStyle.line, lineWidth: 1))
            if calls.completed {
                Label("\(calls.record?.streak() ?? 1) day streak", systemImage: "flame.fill").font(HobbitFont.body(15, weight: .bold))
                Text("Done for today. Your pet is proud. Probably smug, too.").font(HobbitFont.body(14)).foregroundStyle(HobbitStyle.muted)
                Button("Undo today's completion") { calls.markCompleted(false) }.font(HobbitFont.body(13))
            } else {
                HobbitButton(title: "Talk to my pet") { Task { await calls.callNow() } }
                    .disabled(calls.actionBusy || calls.scheduledID != nil || !calls.ready).accessibilityIdentifier("talk-to-pet")
                Button("I did it") { calls.markCompleted(true) }.font(HobbitFont.body(15, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            if calls.scheduledID != nil {
                Text("Your pet will ring shortly. You can lock your iPhone.").font(HobbitFont.body(14))
                Button("Cancel this call") { Task { await calls.cancelScheduled() } }.frame(maxWidth: .infinity)
            } else if !calls.completed {
                Button { Task { await calls.schedule() } } label: {
                    Label("Try an incoming call in 15 seconds", systemImage: "phone.badge.waveform")
                        .font(HobbitFont.body(13)).frame(maxWidth: .infinity)
                }.disabled(calls.actionBusy || !calls.ready || !calls.pushReady)
            }
            if !calls.message.isEmpty { Text(calls.message).font(HobbitFont.body(12)).foregroundStyle(HobbitStyle.muted).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center) }
            if !calls.ready || !calls.pushReady { Button("Retry connection") { Task { await calls.refresh() } }.frame(maxWidth: .infinity) }
            HStack {
                Button("Change pet", action: changePet)
                Spacer()
                Text("One habit. One day at a time.")
            }.font(HobbitFont.body(11)).foregroundStyle(HobbitStyle.muted).padding(.top, 8)
        }
    }
}

struct CelebrationView: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("PACT KEPT", systemImage: "checkmark.circle.fill").font(HobbitFont.label(11)).tracking(1)
                .padding(.horizontal, 14).padding(.vertical, 9).background(HobbitStyle.softGreen, in: Capsule())
            Text("You showed up.")
                .font(HobbitFont.title(34)).tracking(-1.4)
            PetView(pets: pets, expression: "happy").frame(height: 225)
            Text(calls.habit).font(HobbitFont.title(21)).tracking(-0.5)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(calls.record?.streak() ?? 1)").font(HobbitFont.title(44)).tracking(-1)
                Text("day streak").font(HobbitFont.body(18, weight: .bold))
            }.frame(maxWidth: .infinity).padding(18).background(HobbitStyle.softGreen, in: RoundedRectangle(cornerRadius: 24))
            Text("Small counts. See you tomorrow.").font(HobbitFont.body(17))
            HobbitButton(title: "Back to today") { calls.showingCelebration = false }
            Button("Undo completion") { calls.markCompleted(false) }.frame(maxWidth: .infinity).font(HobbitFont.body(13))
        }
    }
}
