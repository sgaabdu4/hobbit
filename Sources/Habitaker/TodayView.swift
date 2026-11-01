import SwiftUI


struct CelebrationView: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("You showed up.")
                .font(HobbitFont.title(34)).tracking(-1.4)
            ZStack {
                Circle().stroke(HobbitStyle.orange.opacity(0.4), lineWidth: 3)
                    .frame(width: 200, height: 200)
                    .scaleEffect(celebrating ? 1.12 : 0.65)
                PetView(pets: pets, expression: "happy")
                    .scaleEffect(celebrating ? 1 : 0.78)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 52)).foregroundStyle(Color.yellow)
                    .shadow(color: HobbitStyle.orange.opacity(0.45), radius: 18)
                    .offset(x: 105, y: 75)
            }.frame(height: 225)
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.55), value: celebrating)
            Text(calls.habit).font(HobbitFont.title(21)).tracking(-0.5)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "flame.fill").font(.system(size: 30)).foregroundStyle(HobbitStyle.orange)
                Text("\(calls.record?.streak() ?? 1)").font(HobbitFont.title(44)).tracking(-1)
                Text("day streak").font(HobbitFont.body(18, weight: .bold))
            }.frame(maxWidth: .infinity).padding(18).background(HobbitStyle.softGreen, in: RoundedRectangle(cornerRadius: 24))
            HobbitButton(title: "Back to today") { calls.showingCelebration = false }
            Button("Undo completion") { calls.markCompleted(false) }.frame(maxWidth: .infinity).font(HobbitFont.body(13))
        }
        .overlay { if !reduceMotion { CompletionConfetti().allowsHitTesting(false).accessibilityHidden(true) } }
        .sensoryFeedback(.success, trigger: celebrating)
        .onAppear { celebrating = true }
    }
}

private struct CompletionConfetti: View {
    @State private var started = Date()
    @State private var running = true

    private func random(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index * 127 + salt * 311)) * 43758.5453
        return value - floor(value)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSince(started)
                guard time < 4.5 else { return }
                let colors: [Color] = [HobbitStyle.orange, .yellow, .mint, .white]
                for index in 0..<120 {
                    let seed = random(index, 1)
                    let delay = random(index, 2) * 0.4
                    let age = time - delay
                    guard age > 0 else { continue }
                    let fromLeft = index % 2 == 0
                    let launchX = fromLeft ? -15.0 : size.width + 15
                    let velocity = 45 + seed * 145
                    let x = launchX + (fromLeft ? 1 : -1) * velocity * age + sin(age * 4 + Double(index)) * 12
                    let y = size.height * 0.65 - (170 + random(index, 3) * 220) * age + 110 * age * age
                    var particle = context
                    particle.opacity = min(1, max(0, (4.5 - time) / 0.8))
                    particle.translateBy(x: x, y: y)
                    particle.rotate(by: .radians(random(index, 4) * 6.28 + age * (seed * 10 - 5)))
                    particle.scaleBy(x: max(0.2, abs(cos(age * 7 + random(index, 5) * 6.28))), y: 1)
                    particle.fill(Path(CGRect(x: -4, y: -7, width: 8, height: 14)), with: .color(colors[index % colors.count]))
                }
            }
        }
        .task {
            started = Date()
            try? await Task.sleep(for: .seconds(4.6))
            running = false
        }
    }
}
