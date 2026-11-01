import Foundation

@MainActor
enum VoiceDiagnostics {
    private static var values: [String: Any] = [:]
    private static var events: [String: Int] = [:]

    static func reset() {
        values = [:]
        events = [:]
        record("stage", "requested")
    }

    static func record(_ key: String, _ value: Any) {
        values[key] = value
        values["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return }
        try? data.write(to: URL.documentsDirectory.appendingPathComponent("voice-check.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func event(_ type: String) {
        events[type, default: 0] += 1
        record("events", events)
    }
}
