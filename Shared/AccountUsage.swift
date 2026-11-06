import Foundation

struct AccountUsage: Codable, Equatable, Sendable {
    struct Summary: Codable, Equatable, Sendable {
        var lifetimeTokens: UInt64?
        var peakDailyTokens: UInt64?
        var longestRunningTurnSec: UInt64?
        var currentStreakDays: UInt64?
        var longestStreakDays: UInt64?
    }

    struct DailyBucket: Codable, Equatable, Sendable {
        let startDate: String
        let tokens: UInt64
    }

    let summary: Summary
    let dailyUsageBuckets: [DailyBucket]?
}

struct ActivityCalendar {
    struct Day {
        let date: Date
        let tokens: UInt64?
        let isFuture: Bool
    }

    struct Week {
        let month: Int?
        let days: [Day]
    }

    static let weekCount = 27
    let todayTokens: UInt64?
    let todayIsLocal: Bool
    let weeks: [Week]
    let peak: UInt64

    init(usage: AccountUsage?, localToday: AccountUsage.DailyBucket? = nil, preferLocalToday: Bool = false,
         date: Date, calendar: Calendar = .localGregorian) {
        let tokensByDate = Dictionary(
            (usage?.dailyUsageBuckets ?? []).map { ($0.startDate, $0.tokens) },
            uniquingKeysWith: { _, latest in latest }
        )
        let today = calendar.startOfDay(for: date)
        let todayKey = calendar.usageDateKey(for: today)
        let accountTokens = tokensByDate[todayKey]
        let localTokens = localToday.flatMap { $0.startDate == todayKey ? $0.tokens : nil }
        todayIsLocal = localTokens != nil && (preferLocalToday || accountTokens == nil)
        todayTokens = todayIsLocal ? localTokens : accountTokens

        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let firstOffset = -daysSinceMonday - (Self.weekCount - 1) * 7
        weeks = (0..<Self.weekCount).map { week in
            let days = (0..<7).compactMap { weekday in
                calendar.date(byAdding: .day, value: firstOffset + week * 7 + weekday, to: today)
            }.map { day in
                Day(date: day, tokens: day <= today ? tokensByDate[calendar.usageDateKey(for: day)] : nil, isFuture: day > today)
            }
            let labelDate = week == 0 ? days.first : days.first {
                !$0.isFuture && calendar.component(.day, from: $0.date) == 1
            }
            return Week(month: labelDate.map { calendar.component(.month, from: $0.date) }, days: days)
        }
        peak = weeks.flatMap(\.days).compactMap(\.tokens).max() ?? 0
    }
}

extension Calendar {
    static var localGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    func usageDateKey(for date: Date) -> String {
        let day = dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}

enum TokenFormat {
    struct Readout: Equatable {
        let digits: String
        let unit: String
    }

    static func lcd(_ tokens: UInt64?) -> Readout {
        guard let tokens else { return Readout(digits: "—", unit: "") }
        guard tokens >= 1_000 else { return Readout(digits: String(tokens), unit: "") }

        let units = ["K", "M", "B", "T", "P", "E"]
        var value = Double(tokens) / 1_000
        var unit = 0
        while (value * 10).rounded() >= 10_000 && unit < units.count - 1 {
            value /= 1_000
            unit += 1
        }
        return Readout(digits: decimal(value), unit: units[unit])
    }

    static func count(_ tokens: UInt64?) -> String {
        guard let tokens else { return "—" }
        switch tokens {
        case 100_000_000_000_000_000...: return compact(tokens, scale: 100_000_000_000_000_000, suffix: "亿亿")
        case 1_000_000_000_000...: return compact(tokens, scale: 1_000_000_000_000, suffix: "万亿")
        case 100_000_000...: return compact(tokens, scale: 100_000_000, suffix: "亿")
        case 10_000...: return compact(tokens, scale: 10_000, suffix: "万")
        default: return String(tokens)
        }
    }

    static func duration(_ seconds: UInt64?) -> String {
        guard let seconds else { return "—" }
        let hours = seconds / 3_600
        let minutes = seconds / 60 % 60
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        if minutes > 0 { return "\(minutes) 分" }
        return "\(seconds) 秒"
    }

    static func days(_ value: UInt64?) -> String {
        value.map { "\($0) 天" } ?? "—"
    }

    private static func compact(_ count: UInt64, scale: Double, suffix: String) -> String {
        let formatted = decimal(Double(count) / scale)
        return (formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted) + suffix
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
