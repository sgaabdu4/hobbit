import SwiftUI

struct AnimatedPetView: View {
    @ObservedObject var pets: PetStore
    var expression = "attentive"
    var audioLevel = 0.0
    var mode = "Gentle"
    var previewing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var envelope = SpeechEnvelope()
    @State private var appeared = Date()

    private var mood: PetMood { PetMood.resolve(expression: expression, mode: mode) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { context in
            let seconds = context.date.timeIntervalSince(appeared)
            let amount = envelope.value(at: context.date)
            let mouth = envelope.mouth(at: context.date)
            let blinkPhase = seconds.truncatingRemainder(dividingBy: 5.3)
            let blinking = !reduceMotion && mouth == 0 && ((blinkPhase > 3.8 && blinkPhase < 3.94) || (blinkPhase > 4.12 && blinkPhase < 4.23))
            let motion = movement(at: seconds, amount: amount)
            Group {
                if let image = pets.animatedFrame(mood: mood, mouth: mouth, blinking: blinking, expression: expression, previewing: previewing) {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "pawprint.fill").resizable().scaledToFit().foregroundStyle(HobbitStyle.orange).padding(60)
                }
            }
            .scaleEffect(x: reduceMotion ? 1 : motion.scaleX, y: reduceMotion ? 1 : motion.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(reduceMotion ? 0 : motion.rotation), anchor: .bottom)
            .offset(x: reduceMotion ? 0 : motion.x, y: reduceMotion ? 0 : motion.y)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mouth == 0 ? "Your pet is \(mood.description)" : "Your \(mood.description) pet is speaking")
            .accessibilityIdentifier("pet-sprite")
            .accessibilityValue(mouth == 0 ? "listening" : "speaking")
        }
        .onAppear { appeared = Date(); envelope.update(level: audioLevel, at: Date()) }
        .onChange(of: audioLevel) { _, level in envelope.update(level: level, at: Date()) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { envelope.update(level: 0, at: Date()) }
        }
    }

    private func movement(at seconds: Double, amount: Double) -> (x: Double, y: Double, rotation: Double, scaleX: Double, scaleY: Double) {
        let breath = sin(seconds * 1.7)
        let speaking = amount > 0.1
        switch mood {
        case .calm:
            return (0, breath * 2.2 - amount * 2, expression == "thinking" ? sin(seconds * 0.8) * 3 : breath * 0.6, 1 - amount * 0.008, 1 + amount * 0.015)
        case .stern:
            return (0, breath * 1.5 - amount * 3, speaking ? sin(seconds * 8) * amount * 1.2 : -1, 1 + amount * 0.012, 1 - amount * 0.008)
        case .furious:
            return (speaking ? sin(seconds * 21) * amount * 1.7 : 0, breath - amount * 4, speaking ? sin(seconds * 12) * amount * 2.2 : -1.5, 1 + amount * 0.02, 1 - amount * 0.012)
        case .happy:
            return (0, -abs(sin(seconds * 3.2)) * 5, sin(seconds * 3.2) * 3, 1 + amount * 0.01, 1 + amount * 0.01)
        }
    }
}
