import Foundation
import Testing
@testable import HabitCore

@Test func mouthFollowsSoundAndClosesWhenSamplesStop() {
    var envelope = SpeechEnvelope()
    let now = Date(timeIntervalSince1970: 100)
    #expect(envelope.mouth(at: now) == 0)
    envelope.update(level: 0.15, at: now)
    #expect(envelope.mouth(at: now.addingTimeInterval(0.10)) == 2)
    envelope.update(level: 0, at: now.addingTimeInterval(0.12))
    #expect(envelope.mouth(at: now.addingTimeInterval(0.40)) == 0)
    envelope.update(level: 0.15, at: now.addingTimeInterval(1))
    #expect(envelope.mouth(at: now.addingTimeInterval(2)) == 0)
}

@Test func invalidAndBackgroundLevelsDoNotAnimateSpeech() {
    var envelope = SpeechEnvelope()
    let now = Date(timeIntervalSince1970: 100)
    for level in [-1.0, Double.nan, Double.infinity, 0.002] {
        envelope.update(level: level, at: now)
        #expect(envelope.mouth(at: now.addingTimeInterval(0.1)) == 0)
    }
}

@Test func coachingModeSetsMoodAndSuccessOverridesAnger() {
    #expect(PetMood.resolve(expression: "attentive", mode: "Gentle") == .calm)
    #expect(PetMood.resolve(expression: "thinking", mode: "Aggressive") == .stern)
    #expect(PetMood.resolve(expression: "attentive", mode: "Unhinged") == .furious)
    #expect(PetMood.resolve(expression: "happy", mode: "Unhinged") == .happy)
    #expect(PetMood.resolve(expression: "calm", mode: "Unhinged") == .calm)
}
