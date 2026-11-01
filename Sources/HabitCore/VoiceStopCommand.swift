import Foundation

public struct VoiceStopCommand {
    private var transcript = ""
    private var lastEnd = 0

    public init() {}

    public mutating func append(_ delta: String, start: Int, end: Int) -> Bool {
        if start - lastEnd > 1800 { transcript = "" }
        lastEnd = end
        transcript = String((transcript + delta).suffix(500))
        return Self.matches(transcript)
    }

    public static func matches(_ text: String) -> Bool {
        let text = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let phrases = #"\b(hang\s*up|end (?:the |this |our )?call|stop (?:the |this |our )?call|stop talking|stop coaching|stop pushing me|leave me alone|disconnect (?:the |this )?call|(?:do not|don't) (?:coach|push) me)\b"#
        guard let expression = try? NSRegularExpression(pattern: phrases) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in expression.matches(in: text, range: range) {
            guard let command = Range(match.range, in: text) else { continue }
            let prefix = text[..<command.lowerBound].components(separatedBy: CharacterSet(charactersIn: ".!?,;\n")).last ?? ""
            if prefix.range(of: #"\b(don't|dont|do not|never|not|if|unless|when)\b"#, options: .regularExpression) == nil { return true }
        }
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words == ["stop"] || words == ["please", "stop"] || words == ["pip", "stop"]
    }
}
