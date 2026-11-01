import Foundation

public struct HabitRecord: Codable, Equatable, Sendable {
    public var habit: String
    public var mode: String
    public var hour: Int
    public var minute: Int
    public var timeZone: String
    public var paused: Bool
    public var completedDays: [String]

    public init(habit: String, mode: String, hour: Int = 15, minute: Int = 0, timeZone: String = TimeZone.current.identifier, paused: Bool = false, completedDays: [String] = []) {
        self.habit = habit
        self.mode = mode
        self.hour = hour
        self.minute = minute
        self.timeZone = timeZone
        self.paused = paused
        self.completedDays = completedDays
    }

    public var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZone) ?? .current
        value.firstWeekday = 2
        return value
    }

    public func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public func isCompleted(on date: Date = Date()) -> Bool { completedDays.contains(dayKey(date)) }

    public mutating func complete(_ done: Bool, on date: Date = Date()) {
        let key = dayKey(date)
        completedDays.removeAll { $0 == key }
        if done { completedDays.append(key) }
        completedDays = Array(completedDays.sorted().suffix(730))
    }

    public func streak(on date: Date = Date()) -> Int {
        var current = calendar.startOfDay(for: date)
        if !isCompleted(on: current) { current = calendar.date(byAdding: .day, value: -1, to: current)! }
        var count = 0
        while isCompleted(on: current) {
            count += 1
            current = calendar.date(byAdding: .day, value: -1, to: current)!
        }
        return count
    }
}
