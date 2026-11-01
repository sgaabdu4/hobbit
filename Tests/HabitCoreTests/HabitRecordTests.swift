import Foundation
import Testing
@testable import HabitCore

@Test func completionRollsOverAndUndoPreservesHistory() {
    var record = HabitRecord(habit: "Stretch", mode: "Gentle", timeZone: "Europe/London")
    let day = ISO8601DateFormatter().date(from: "2026-11-01T23:59:00Z")!
    record.complete(true, on: day)
    record.complete(true, on: day)
    #expect(record.completedDays.count == 1)
    #expect(record.isCompleted(on: day))
    #expect(!record.isCompleted(on: day.addingTimeInterval(120)))
    #expect(record.streak(on: day.addingTimeInterval(120)) == 1)
    record.complete(true, on: day.addingTimeInterval(120))
    #expect(record.streak(on: day.addingTimeInterval(120)) == 2)
    record.complete(false, on: day.addingTimeInterval(120))
    #expect(record.completedDays == ["2026-11-01"])
}

@Test func streakUsesCalendarDaysAcrossClockChanges() {
    let record = HabitRecord(habit: "Stretch", mode: "Gentle", timeZone: "Europe/London", completedDays: ["2026-10-24", "2026-10-25", "2026-10-26"])
    let date = ISO8601DateFormatter().date(from: "2026-10-26T10:00:00Z")!
    #expect(record.streak(on: date) == 3)
    #expect(record.streak(on: date.addingTimeInterval(172800)) == 0)
}
