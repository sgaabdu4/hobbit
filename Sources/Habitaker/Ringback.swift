import AVFoundation

@MainActor
final class Ringback {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil, let url = Bundle.main.url(forResource: "hobbit-ring", withExtension: "caf") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.45
            player.prepareToPlay()
            self.player = player
            VoiceDiagnostics.record("ringbackStarted", player.play())
        } catch { VoiceDiagnostics.record("ringbackError", (error as NSError).code) }
    }

    func stop() {
        player?.stop()
        player = nil
        VoiceDiagnostics.record("ringbackStopped", true)
    }
}
