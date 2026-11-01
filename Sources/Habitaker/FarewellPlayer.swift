import AVFoundation

@MainActor
final class FarewellPlayer: NSObject, AVAudioPlayerDelegate {
    var onFinished: (() -> Void)?
    var onLevel: ((Double) -> Void)?
    private var player: AVAudioPlayer?
    private var meter: Timer?

    func play(mode: String, completed: Bool) -> Bool {
        stop()
        let name = (completed ? "completion-" : "farewell-") + mode.lowercased()
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.delegate = self
        player.isMeteringEnabled = true
        player.volume = 1
        self.player = player
        guard player.play() else { stop(); return false }
        meter = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                player.updateMeters()
                self.onLevel?(pow(10, Double(player.averagePower(forChannel: 0)) / 20))
            }
        }
        return true
    }

    func stop() {
        meter?.invalidate()
        meter = nil
        player?.stop()
        player = nil
        onLevel?(0)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            stop()
            VoiceDiagnostics.record("farewellFinished", flag)
            VoiceDiagnostics.record("farewellFinishedAt", Date().timeIntervalSince1970)
            onFinished?()
        }
    }
}
