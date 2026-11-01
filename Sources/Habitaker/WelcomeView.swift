import SwiftUI

struct WelcomeView: View {
    @ObservedObject var auth: AuthCoordinator
    @ObservedObject var pets: PetStore
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 22) {
                HobbitWordmark().padding(.bottom, 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Small pet.").foregroundStyle(HobbitStyle.ink)
                    Text("Big get-up energy.").foregroundStyle(HobbitStyle.orange)
                }.font(HobbitFont.title(34)).tracking(-1.4)
                Spacer(minLength: 0)
                PetView(pets: pets).frame(height: min(235, max(100, geometry.size.height - 360)))
                    .overlay(alignment: .topTrailing) {
                        Text("Excuses? Interesting.").font(HobbitFont.body(11, weight: .semibold)).padding(12)
                            .background(HobbitStyle.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HobbitStyle.line, lineWidth: 1))
                            .rotationEffect(.degrees(7)).padding(.top, 8)
                    }
                Text("Pip").font(HobbitFont.body(14)).foregroundStyle(HobbitStyle.muted).frame(maxWidth: .infinity)
                Spacer(minLength: 8)
                HobbitButton(title: auth.busy ? "Signing you in..." : "Continue with ChatGPT", action: auth.signIn)
                    .disabled(auth.busy).accessibilityIdentifier("chatgpt-sign-in")
                if auth.busy { ProgressView().frame(maxWidth: .infinity) }
                if auth.message != "Sign in to meet your AI habit companion." {
                    Text(auth.message).font(HobbitFont.body(12)).foregroundStyle(HobbitStyle.muted).accessibilityIdentifier("auth-status")
                }
            }.padding(24).frame(width: geometry.size.width, height: geometry.size.height).foregroundStyle(HobbitStyle.ink)
        }.background(HobbitStyle.cream.ignoresSafeArea())
    }
}
