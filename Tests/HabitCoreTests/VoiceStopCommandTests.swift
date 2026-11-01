import Testing
@testable import HabitCore

@Test(arguments: ["Hang up the call.", "Pip, hang up.", "Can you please end this call?", "I told you to hang up", "Stop talking.", "Leave me alone.", "Please stop.", "Don't coach me."])
func explicitVoiceExitEndsTheCall(_ phrase: String) {
    #expect(VoiceStopCommand.matches(phrase))
}

@Test(arguments: ["I don't want to do it.", "Don't hang up.", "Can you not hang up?", "What happens if I say hang up?", "Never end the call.", "I will stop procrastinating."])
func reluctanceAndNegatedExitsDoNotEndTheCall(_ phrase: String) {
    #expect(!VoiceStopCommand.matches(phrase))
}

@Test func stopCommandSurvivesTranscriptFragmentsWithoutKeepingOldNegation() {
    var command = VoiceStopCommand()
    let first = command.append("Don't hang", start: 0, end: 600)
    let negated = command.append(" up.", start: 600, end: 900)
    let next = command.append("Please hang", start: 4000, end: 4400)
    let commandComplete = command.append(" up", start: 4400, end: 4800)
    #expect(!first)
    #expect(!negated)
    #expect(!next)
    #expect(commandComplete)
}
