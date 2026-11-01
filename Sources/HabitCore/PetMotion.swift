import Foundation

public enum PetMood: Int, Sendable {
    case calm, stern, furious, happy

    public static func resolve(expression: String, mode: String) -> PetMood {
        if expression == "happy" { return .happy }
        if expression == "calm" { return .calm }
        if expression == "furious" || mode == "Unhinged" { return .furious }
        if expression == "angry" || mode == "Aggressive" { return .stern }
        return .calm
    }

    public var description: String {
        switch self {
        case .calm: "attentive"
        case .stern: "determined"
        case .furious: "furious"
        case .happy: "happy"
        }
    }
}

public struct SpeechEnvelope: Sendable {
    private var initial = 0.0
    private var target = 0.0
    private var timestamp = Date.distantPast

    public init() {}

    public mutating func update(level: Double, at date: Date) {
        initial = value(at: date)
        let safe = level.isFinite ? min(1, max(0, level)) : 0
        target = safe < 0.004 ? 0 : min(1, (sqrt(safe) - 0.06) / 0.30)
        timestamp = date
    }

    public func value(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(timestamp))
        let duration = target > initial ? 0.035 : 0.075
        let value = target + (initial - target) * exp(-min(elapsed, 0.25) / duration)
        let release = elapsed > 0.25 ? exp(-(elapsed - 0.25) / 0.085) : 1
        return min(1, max(0, value * release))
    }

    public func mouth(at date: Date) -> Int {
        let amount = value(at: date)
        return amount < 0.10 ? 0 : amount < 0.55 ? 1 : 2
    }
}
