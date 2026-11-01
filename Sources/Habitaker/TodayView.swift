import SwiftUI


struct CelebrationView: View {
    @ObservedObject var calls: CallCoordinator
    @ObservedObject var pets: PetStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("You showed up.")
                .font(HobbitFont.title(34)).tracking(-1.4)
            PetView(pets: pets, expression: "happy").frame(height: 225)
            Text(calls.habit).font(HobbitFont.title(21)).tracking(-0.5)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(calls.record?.streak() ?? 1)").font(HobbitFont.title(44)).tracking(-1)
                Text("day streak").font(HobbitFont.body(18, weight: .bold))
            }.frame(maxWidth: .infinity).padding(18).background(HobbitStyle.softGreen, in: RoundedRectangle(cornerRadius: 24))
            HobbitButton(title: "Back to today") { calls.showingCelebration = false }
            Button("Undo completion") { calls.markCompleted(false) }.frame(maxWidth: .infinity).font(HobbitFont.body(13))
        }
    }
}
