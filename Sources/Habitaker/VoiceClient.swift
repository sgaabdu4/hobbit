import Foundation
import WebRTC

@MainActor
final class VoiceClient: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    private let factory = RTCPeerConnectionFactory()
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var microphone: RTCAudioTrack?
    private var meter: Timer?
    private var closeTimer: Timer?
    private var sessionStarted = false
    private var greeting: String?
    private var lastDiagnostic = Date.distantPast

    func connect(habit: String, mode: String, callID: String?) async throws {
        VoiceDiagnostics.record("stage", "preparing_audio")
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw AuthFailure.invalid("Audio could not start. End this call and try again.")
        }
        self.peer = peer
        let track = factory.audioTrack(with: factory.audioSource(with: constraints), trackId: "habitaker-mic")
        microphone = track
        peer.add(track, streamIds: ["habitaker-audio"])
        channel = peer.dataChannel(forLabel: "oai-events", configuration: RTCDataChannelConfiguration())
        channel?.delegate = self
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peer.offer(for: RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)) { offer, error in
                if let error { continuation.resume(throwing: error) }
                else if let offer { continuation.resume(returning: offer) }
                else { continuation.resume(throwing: AuthFailure.invalid("Audio offer could not be created.")) }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(offer) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        let deadline = Date().addingTimeInterval(10)
        while peer.iceGatheringState != .complete, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard peer.iceGatheringState == .complete, let sdp = peer.localDescription?.sdp else {
            throw AuthFailure.invalid("The network could not prepare this call. Try another Wi-Fi network.")
        }
        var body: [String: Any] = ["sdp": sdp, "habit": habit, "mode": mode]
        if let callID { body["callID"] = callID }
        VoiceDiagnostics.record("stage", "requesting_session")
        let response = try await Backend.shared.request("voice", method: "POST", body: body)
        VoiceDiagnostics.record("stage", "session_created")
        greeting = response["greeting"] as? String
        try Task.checkCancellation()
        guard let transport = response["transport"] as? [String: Any], let answer = transport["sdp"] as? String else {
            throw AuthFailure.invalid("Voice returned no audio connection. Try again.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer)) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        await MainActor.run {
            self.meter = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let report = await self?.peer?.statistics() else { return }
                    let level = report.statistics.values.filter { $0.type == "inbound-rtp" }
                        .compactMap { ($0.values["audioLevel"] as? NSNumber)?.doubleValue }.max() ?? 0
                    self?.onLevel?(level)
                    if let self, Date().timeIntervalSince(self.lastDiagnostic) > 1 {
                        self.lastDiagnostic = Date()
                        let stats = report.statistics.values
                        VoiceDiagnostics.record("audio", [
                            "enabled": RTCAudioSession.sharedInstance().isAudioEnabled,
                            "receivedBytes": stats.filter { $0.type == "inbound-rtp" }.compactMap { ($0.values["bytesReceived"] as? NSNumber)?.intValue }.reduce(0, +),
                            "sentBytes": stats.filter { $0.type == "outbound-rtp" }.compactMap { ($0.values["bytesSent"] as? NSNumber)?.intValue }.reduce(0, +),
                            "inputLevel": stats.filter { $0.type == "media-source" }.compactMap { ($0.values["audioLevel"] as? NSNumber)?.doubleValue }.max() ?? 0,
                            "outputLevel": level,
                            "route": RTCAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }
                        ])
                    }
                }
            }
        }
    }

    func send(_ event: [String: Any]) {
        guard sessionStarted, let data = try? JSONSerialization.data(withJSONObject: event) else { return }
        channel?.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    func mute(_ muted: Bool) { microphone?.isEnabled = !muted }

    func close() {
        microphone?.isEnabled = false
        meter?.invalidate()
        if sessionStarted, channel?.readyState == .open {
            send(["type": "session.close"])
            closeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
                Task { @MainActor in self.shutdown() }
            }
        } else { shutdown() }
    }

    private func shutdown() {
        closeTimer?.invalidate()
        meter?.invalidate()
        microphone?.isEnabled = false
        channel?.close()
        peer?.close()
        peer = nil
        channel = nil
        sessionStarted = false
    }

    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let state = dataChannel.readyState.rawValue
        Task { @MainActor in VoiceDiagnostics.record("dataChannelState", state) }
    }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        DispatchQueue.main.async { [weak self] in
            guard let self, let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let type = event["type"] as? String { VoiceDiagnostics.event(type) }
            if event["type"] as? String == "error", let error = event["error"] as? [String: Any], let code = error["code"] as? String {
                VoiceDiagnostics.record("apiErrorCode", code)
            }
            if event["type"] as? String == "session.started" {
                self.sessionStarted = true
                if let greeting = self.greeting {
                    self.send(["type": "session.commentary.append", "event_id": UUID().uuidString, "delegation_id": NSNull(), "content": greeting])
                    self.greeting = nil
                }
            }
            if event["type"] as? String == "session.closed" { self.shutdown() }
            self.onEvent?(event)
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in VoiceDiagnostics.record("iceState", newState.rawValue) }
        if newState == .failed { DispatchQueue.main.async { [weak self] in self?.onFailure?("The audio connection was lost. Try calling again.") } }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
