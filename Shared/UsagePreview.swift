import Foundation

extension UsageSnapshot {
    static func preview(at date: Date) -> Self {
        let calendar = Calendar.localGregorian
        let levels: [UInt64] = [0, 24_000, 90_000, 250_000, 600_000]
        var random = UInt32(27)
        let buckets = (0..<(ActivityCalendar.weekCount * 7)).compactMap { index -> AccountUsage.DailyBucket? in
            guard let day = calendar.date(byAdding: .day, value: -index, to: date) else { return nil }
            random = random &* 1_664_525 &+ 1_013_904_223
            let slot = Int(random >> 16) % levels.count
            return .init(startDate: calendar.usageDateKey(for: day), tokens: index == 0 ? 128_600 : levels[slot])
        }
        let summary = AccountUsage.Summary(
            lifetimeTokens: 36_320_000_000,
            peakDailyTokens: 5_390_000_000,
            longestRunningTurnSec: 80_640,
            currentStreakDays: 9,
            longestStreakDays: 12
        )
        return Self(usage: AccountUsage(summary: summary, dailyUsageBuckets: buckets), fetchedAt: date)
    }
}
