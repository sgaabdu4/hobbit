import SwiftUI

enum HobbitFont {
    static func title(_ size: CGFloat = 32) -> Font { .custom("Manrope", size: size, relativeTo: .largeTitle).weight(.heavy) }
    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font { .custom("DM Sans", size: size, relativeTo: .body).weight(weight) }
    static func label(_ size: CGFloat = 11) -> Font { .custom("DM Sans", size: size, relativeTo: .caption).weight(.bold) }
}

struct HobbitWordmark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "waveform").font(.system(size: 17, weight: .medium)).foregroundStyle(HobbitStyle.orange)
            Text("hobbit").font(HobbitFont.title(23)).tracking(-1)
            Text(".").font(HobbitFont.title(23)).foregroundStyle(HobbitStyle.orange).padding(.leading, -5)
        }.foregroundStyle(HobbitStyle.ink)
    }
}

struct HabitWeek: View {
    let record: HabitRecord?
    private var days: [Date] {
        let calendar = record?.calendar ?? Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let today = (record?.calendar ?? Calendar.current).isDate(day, inSameDayAs: Date())
                VStack(spacing: 7) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(HobbitFont.label(10)).foregroundStyle(HobbitStyle.muted)
                    ZStack {
                        Circle().fill(today ? HobbitStyle.ink : Color.clear)
                        if record?.isCompleted(on: day) == true {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        } else { Text(day.formatted(.dateTime.day())).font(HobbitFont.body(13, weight: .medium)) }
                    }.foregroundStyle(today ? HobbitStyle.cream : HobbitStyle.ink).frame(height: 34)
                }.frame(maxWidth: .infinity)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (record?.isCompleted(on: day) == true ? ", completed" : ""))
            }
        }
    }
}
