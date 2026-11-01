import AVFoundation
import CallKit
import Combine
import PushKit
import UIKit
import WebRTC

@MainActor
final class CallCoordinator: NSObject, ObservableObject, PKPushRegistryDelegate, CXProviderDelegate {
    static let shared = CallCoordinator()
    @Published var habit = UserDefaults.standard.string(forKey: "habit") ?? "Stretch for two minutes"
    @Published var mode = UserDefaults.standard.string(forKey: "mode") ?? "Gentle"
    @Published var message = "One small habit. A pet to help you start."
    @Published var active = false
    @Published var connecting = false
    @Published var ready = false
    @Published var pushReady = false
    @Published var muted = false
    @Published var completed = UserDefaults.standard.object(forKey: "completedAt")
        .flatMap { $0 as? Date }.map { Calendar.current.isDateInToday($0) } ?? false
    @Published var expression = "attentive"
    @Published var audioLevel = 0.0
    @Published var scheduledID: String?
    @Published var record: HabitRecord?
    @Published var saving = false
    @Published var actionBusy = false
    @Published var nextCall: Date?
    @Published var caption = ""
    @Published var showingCelebration = false
    @Published var onboardingVoice = false
    @Published var checkingHabit = false
    @Published var draftHabit: String?
    @Published var draftHour = 15
    @Published var draftMinute = 0
    @Published var draftDefaultTime = false
    private var userTranscript = ""
    private var progressPending = UserDefaults.standard.bool(forKey: "progressPending")
    private var syncingProgress = false
    private let provider = CXProvider(configuration: {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        config.ringtoneSound = "hobbit-ring.caf"
        return config
    }())
    private let controller = CXCallController()
    private var registry: PKPushRegistry?
    private var audioRouteObserver: NSObjectProtocol?
    private var token: String?
    private var callUUID: UUID?
    private var incomingID: String?
    private var voice: VoiceClient?
    private var connectionTask: Task<Void, Never>?
    private var callDeadline: Task<Void, Never>?
    private var delegations = Set<String>()
    private var handled = Set<String>()
    private var sourceOrder: [String: Int] = [:]
    private var directionOrder: [String: Int] = [:]
    private var sequence = 0
    private var pendingCommentary: [String: (String, String)] = [:]
    private let ringback = Ringback()
    @Published private(set) var ringing = false

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "habitRecord") {
            record = try? JSONDecoder().decode(HabitRecord.self, from: data)
            if let record { habit = record.habit; mode = record.mode; completed = record.isCompleted() }
        }
        provider.setDelegate(self, queue: .main)
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.categoryOptions = [.allowBluetoothHFP, .defaultToSpeaker]
        RTCAudioSessionConfiguration.setWebRTC(configuration)
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
        audioRouteObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.audioRouteChanged() }
        }
    }

    func refresh() async {
        if let record { completed = record.isCompleted() }
        do {
            if let token { _ = try await Backend.shared.request("device", method: "POST", body: ["token": token]) }
            let health = try await Backend.shared.request("health")
            ready = health["voiceReady"] as? Bool == true
            pushReady = health["pushReady"] as? Bool == true && health["deviceRegistered"] as? Bool == true
            if progressPending { await syncProgress() }
            if record != nil { applySchedule(try await Backend.shared.request("schedule")) }
            if let id = scheduledID {
                let call = try await Backend.shared.request("calls/" + id)
                if ["failed", "missed", "ended"].contains(call["status"] as? String ?? "") {
                    scheduledID = nil
                    message = call["error"] as? String ?? "The call has ended. You can try again."
                }
            }
            if !ready { message = "Voice setup is incomplete on the server. Retry after setup." }
        } catch { ready = false; pushReady = false; message = "Cannot reach your Mac. Keep it awake on the same Wi-Fi, then retry." }
    }

    func savePlan(habit: String, mode: String, time: Date, paused: Bool = false) async -> Bool {
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let draft = HabitRecord(habit: habit.trimmingCharacters(in: .whitespacesAndNewlines), mode: mode,
                               hour: parts.hour ?? 15, minute: parts.minute ?? 0, paused: paused,
                               completedDays: record?.completedDays ?? [])
        do {
            let result = try await Backend.shared.request("schedule", method: "PUT", body: [
                "habit": draft.habit, "mode": draft.mode, "hour": draft.hour, "minute": draft.minute,
                "timeZone": draft.timeZone, "paused": paused
            ])
            record = draft
            self.habit = draft.habit
            self.mode = draft.mode
            saveHabit()
            persistRecord()
            applySchedule(result)
            message = paused ? "Daily calls are paused. Resume whenever you're ready." : "Daily call saved. Your pet will ring at the time you chose."
            await syncProgress()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func togglePause() async {
        guard let record else { return }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: record.timeZone) ?? .current
        let time = calendar.date(bySettingHour: record.hour, minute: record.minute, second: 0, of: Date()) ?? Date()
        _ = await savePlan(habit: record.habit, mode: record.mode, time: time, paused: !record.paused)
    }

    private func persistRecord() {
        if let record, let data = try? JSONEncoder().encode(record) { UserDefaults.standard.set(data, forKey: "habitRecord") }
    }

    private func applySchedule(_ result: [String: Any]) {
        nextCall = (result["nextCallAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        if let plan = result["plan"] as? [String: Any], let error = plan["lastError"] as? String { message = error }
    }

    private func syncProgress() async {
        guard record != nil, !syncingProgress else { return }
        syncingProgress = true
        defer { syncingProgress = false }
        repeat {
            guard let snapshot = record else { break }
            do {
                let result = try await Backend.shared.request("progress", method: "PUT", body: ["completedDays": snapshot.completedDays])
                progressPending = record?.completedDays != snapshot.completedDays
                if !progressPending { applySchedule(result) }
            } catch {
                progressPending = true
                message = "Progress saved on this iPhone. Reconnect to update your next call."
                break
            }
        } while progressPending
        UserDefaults.standard.set(progressPending, forKey: "progressPending")
    }

    func saveHabit() {
        habit = String(habit.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        UserDefaults.standard.set(habit, forKey: "habit")
        UserDefaults.standard.set(mode, forKey: "mode")
    }

    private func permission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        if !granted { message = "Microphone access is off. Enable it in iPhone Settings to talk with your pet." }
        return granted
    }

    func callNow() async {
        guard !actionBusy, !active, !connecting, callUUID == nil, scheduledID == nil, !habit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        actionBusy = true
        defer { actionBusy = false }
        guard await permission() else { return }
        saveHabit()
        let id = UUID()
        VoiceDiagnostics.reset()
        callUUID = id
        connecting = true
        do {
            try await controller.request(CXTransaction(action: CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: "Hobbit pet"))))
        } catch { connecting = false; callUUID = nil; message = "iPhone could not start the call. Try again." }
    }

    func beginOnboarding() async {
        guard !active, !connecting else { return }
        userTranscript = ""
        draftHabit = nil
        onboardingVoice = true
        await callNow()
        if !active && !connecting { onboardingVoice = false }
    }

    func checkSpokenHabit() async {
        guard !checkingHabit else { return }
        let transcript = userTranscript
        checkingHabit = true
        end()
        defer { checkingHabit = false; userTranscript = "" }
        do {
            let result = try await Backend.shared.request("habit-draft", method: "POST", body: ["transcript": transcript])
            guard let habit = result["habit"] as? String, let hour = result["hour"] as? Int, let minute = result["minute"] as? Int else {
                throw AuthFailure.invalid("Your habit could not be understood. Type it instead.")
            }
            draftHour = hour
            draftMinute = minute
            draftDefaultTime = result["defaultTime"] as? Bool ?? true
            draftHabit = habit
            message = "Check your habit and call time before saving."
        } catch { message = error.localizedDescription }
    }

    func schedule() async {
        guard !actionBusy, scheduledID == nil, callUUID == nil, !active, !connecting else { return }
        actionBusy = true
        defer { actionBusy = false }
        guard await permission() else { return }
        saveHabit()
        do {
            let result = try await Backend.shared.request("calls", method: "POST", body: ["habit": habit, "mode": mode, "delaySeconds": 15])
            scheduledID = result["id"] as? String
            message = "Your pet will call in 15 seconds. Lock your iPhone to try it."
        } catch { message = error.localizedDescription }
    }

    func cancelScheduled() async {
        guard let id = scheduledID else { return }
        do { _ = try await Backend.shared.request("calls/" + id, method: "DELETE"); scheduledID = nil; message = "Call cancelled. You can schedule another." }
        catch { message = "Cancellation could not reach the server. The scheduled call may still ring." }
    }

    func end() {
        guard let id = callUUID else { return }
        controller.request(CXTransaction(action: CXEndCallAction(call: id))) { _ in }
    }

    func toggleMute() {
        guard let id = callUUID else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: id, muted: !muted))) { _ in }
    }

    func markCompleted(_ done: Bool) {
        completed = done
        record?.complete(done)
        persistRecord()
        showingCelebration = done
        progressPending = true
        UserDefaults.standard.set(true, forKey: "progressPending")
        Task { await syncProgress() }
        if done { UserDefaults.standard.set(Date(), forKey: "completedAt") }
        else { UserDefaults.standard.removeObject(forKey: "completedAt") }
        expression = done ? "happy" : "attentive"
        message = done ? "Habit done. Saved on this iPhone. See you tomorrow." : "Completion undone. Your habit is ready again."
    }

    func checkDay() {
        if let record, completed != record.isCompleted() {
            completed = record.isCompleted()
            showingCelebration = false
            expression = completed ? "happy" : "attentive"
        }
    }

    private func startVoice() {
        callDeadline?.cancel()
        VoiceDiagnostics.record("stage", "starting_voice")
        ringing = true
        let voice = VoiceClient()
        self.voice = voice
        voice.onEvent = { [weak self] event in self?.receive(event) }
        voice.onLevel = { [weak self] level in
            self?.audioLevel = level
            if level > 0.008 { self?.speechBegan() }
        }
        voice.onFailure = { [weak self] message in self?.fail(message) }
        active = true
        caption = ""
        connecting = true
        message = "Ringing Pip..."
        if RTCAudioSession.sharedInstance().isAudioEnabled { ringback.start() }
        connectionTask = Task {
            do { try await voice.connect(habit: habit, mode: mode, callID: incomingID, onboarding: onboardingVoice) }
            catch { if !Task.isCancelled { fail(error.localizedDescription) } }
        }
        callDeadline = Task {
            try? await Task.sleep(for: .seconds(40))
            guard !Task.isCancelled else { return }
            if connecting || ringing { fail("Your pet did not answer. Check Wi-Fi and try again."); return }
            try? await Task.sleep(for: .seconds(140))
            guard !Task.isCancelled else { return }
            message = "Your three-minute call has ended. Your progress is saved."
            end()
        }
    }

    private func fail(_ message: String) {
        VoiceDiagnostics.record("stage", "failed")
        self.message = message
        if let id = callUUID { provider.reportCall(with: id, endedAt: Date(), reason: .failed) }
        finish()
    }

    private func finish() {
        ringing = false
        ringback.stop()
        connectionTask?.cancel()
        callDeadline?.cancel()
        voice?.onEvent = nil
        voice?.onFailure = nil
        voice?.onLevel = nil
        voice?.close()
        voice = nil
        active = false
        onboardingVoice = false
        connecting = false
        muted = false
        audioLevel = 0
        callUUID = nil
        delegations.removeAll()
        handled.removeAll()
        sourceOrder.removeAll()
        directionOrder.removeAll()
        pendingCommentary.removeAll()
        if let incomingID { Task { _ = try? await Backend.shared.request("calls/" + incomingID, method: "DELETE") } }
        incomingID = nil
    }

    private func speechBegan() {
        guard ringing else { return }
        ringing = false
        ringback.stop()
        message = "You're connected. Tell your pet how it's going."
    }

    private func receive(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        if type == "session.output_transcript.delta", let delta = event["delta"] as? String {
            caption = String((caption + delta).suffix(320))
        }
        if onboardingVoice, type == "session.input_transcript.delta", let delta = event["delta"] as? String {
            userTranscript = String((userTranscript + delta).prefix(12000))
        }
        if type == "session.started" {
            connecting = false
            message = "Your pet is answering..."
            if incomingID == nil, let id = callUUID { provider.reportOutgoingCall(with: id, connectedAt: Date()) }
        } else if type == "session.closed" {
            if active { end() }
        } else if type == "error" { fail("Voice hit a problem. End the call and try again.") }
        else if type == "session.delegation.created", let delegation = event["delegation"] as? [String: Any], let id = delegation["id"] as? String {
            delegations.insert(id)
        } else if type.hasSuffix("transcript.delta"), let id = event["event_id"] as? String {
            sequence += 1
            sourceOrder[id] = sequence
        } else if type == "decision.item.created", let clientID = event["client_event_id"] as? String, let pending = pendingCommentary.removeValue(forKey: clientID) {
            voice?.send(["type": "session.commentary.append", "delegation_id": pending.0, "content": pending.1])
        } else if type == "decision.event", let inner = event["event"] as? [String: Any],
                  inner["type"] as? String == "decision.completed", let decision = inner["decision"] as? [String: Any],
                  let answers = decision["answers"] as? [[String: Any]] {
            if let delegation = event["delegation_id"] as? String, delegations.contains(delegation), !handled.contains(delegation) {
                handled.insert(delegation)
                let action = answers.first { $0["name"] as? String == "habit_action" }?["choice"] as? String
                if action == "stop" { end(); return }
                if action == "completed" { markCompleted(true) }
                let result = action == "completed" ? "Habit completion was saved on this iPhone." : action == "starting" ? "The user is starting. The habit is not yet marked complete." : "No habit change was made."
                let clientID = UUID().uuidString
                pendingCommentary[clientID] = (delegation, result)
                voice?.send(["type": "decision.item.create", "event_id": clientID, "item": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Latest app state: " + result]]]])
            } else if event["trigger_id"] != nil, let source = event["source_event_id"] as? String,
                      let direction = event["source_event_type"] as? String, let order = sourceOrder[source], order > (directionOrder[direction] ?? 0),
                      let next = answers.first(where: { $0["name"] as? String == "expression" })?["choice"] as? String,
                      ["happy", "thinking", "attentive"].contains(next) {
                directionOrder[direction] = order
                expression = next
            }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let value = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in token = value; await refresh() }
    }
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        Task { @MainActor in token = nil; pushReady = false }
    }
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        MainActor.assumeIsolated { reportIncoming(payload, completion: completion) }
    }
    private func reportIncoming(_ payload: PKPushPayload, completion: @escaping () -> Void) {
        let incoming = payload.dictionaryPayload["call_id"] as? String
        let id = incoming.flatMap(UUID.init(uuidString:)) ?? UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "Hobbit pet")
        update.localizedCallerName = "Your Hobbit pet"
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            Task { @MainActor in
                if error == nil, let self {
                    self.callUUID = id
                    self.incomingID = incoming
                    self.scheduledID = nil
                    self.callDeadline = Task {
                        try? await Task.sleep(for: .seconds(45))
                        guard !Task.isCancelled, self.callUUID == id, !self.active else { return }
                        self.provider.reportCall(with: id, endedAt: Date(), reason: .unanswered)
                        self.message = "You missed your pet's call. Try again when you're ready."
                        self.finish()
                    }
                }
                completion()
            }
        }
    }
    nonisolated func providerDidReset(_ provider: CXProvider) { MainActor.assumeIsolated { finish() } }
    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        MainActor.assumeIsolated {
        do { try configureAudio(); startVoice(); action.fulfill() }
        catch { action.fail(); fail("Audio could not start. Try again.") }
        }
    }
    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
        do { try configureAudio(); startVoice(); action.fulfill() }
        catch { action.fail(); fail("Audio could not start. Try again.") }
        }
    }
    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) { MainActor.assumeIsolated { finish(); action.fulfill() } }
    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) { MainActor.assumeIsolated { muted = action.isMuted; voice?.mute(muted); action.fulfill() } }
    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        Task { @MainActor in
            VoiceDiagnostics.record("audioActivated", true)
            preferLoudspeaker()
            if active, ringing { ringback.start() }
        }
    }
    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    }
    private func configureAudio() throws {
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        defer { audio.unlockForConfiguration() }
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
    }

    private func audioRouteChanged() {
        guard active, RTCAudioSession.sharedInstance().isAudioEnabled else { return }
        preferLoudspeaker()
    }

    private func preferLoudspeaker() {
        let audio = RTCAudioSession.sharedInstance()
        guard audio.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) else { return }
        audio.lockForConfiguration()
        defer { audio.unlockForConfiguration() }
        do {
            try audio.overrideOutputAudioPort(.speaker)
            VoiceDiagnostics.record("speakerOverride", true)
        } catch { VoiceDiagnostics.record("speakerOverrideError", (error as NSError).code) }
    }
}
