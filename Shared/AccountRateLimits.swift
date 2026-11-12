import Foundation

struct AccountRateLimits: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        var usedPercent: Int
        var windowDurationMins: Int?
        var resetsAt: Int64?
    }

    struct Credits: Codable, Equatable, Sendable {
        var hasCredits: Bool
        var unlimited: Bool
        var balance: String?

        var formattedBalance: String {
            if unlimited { return String(localized: "不限量") }
            guard let balance, let amount = Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX")),
                  amount >= 0 else { return hasCredits ? "—" : "0" }
            let formatter = NumberFormatter()
            formatter.locale = UsageLocale.current
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter.string(from: amount as NSDecimalNumber) ?? "—"
        }
    }

    struct Bucket: Codable, Equatable, Sendable {
        var limitId: String?
        var primary: Window?
        var secondary: Window?
        var credits: Credits?
        var rateLimitReachedType: String?

        var weekly: Window? {
            [primary, secondary].compactMap { $0 }.first { $0.windowDurationMins == 7 * 24 * 60 }
        }
    }

    enum Source: Equatable { case weekly, credits, unknown }

    var rateLimits: Bucket
    var rateLimitsByLimitId: [String: Bucket]?
    var ordinaryUsageAllowed: Bool?

    var codex: Bucket {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }

    var source: Source {
        // The backend's included-usage decision takes precedence over window percentages.
        if ordinaryUsageAllowed == true { return codex.weekly == nil ? .unknown : .weekly }
        if ordinaryUsageAllowed == false { return codex.credits == nil ? .unknown : .credits }

        // Older servers omit ordinaryUsageAllowed. Fall back only to their current
        // window/limit state; having a credit balance alone never selects credits.
        let exhausted = [codex.primary, codex.secondary].compactMap { $0 }.contains { $0.usedPercent >= 100 }
        if exhausted || codex.rateLimitReachedType != nil {
            return codex.credits == nil ? (codex.weekly == nil ? .unknown : .weekly) : .credits
        }
        return codex.weekly == nil ? .unknown : .weekly
    }

    var label: String {
        switch source {
        case .weekly: return String(localized: "周额度")
        case .credits: return String(localized: "积分")
        case .unknown: return String(localized: "额度")
        }
    }

    var value: String {
        switch source {
        case .weekly:
            guard let weekly = codex.weekly else { return "—" }
            let remaining = max(0, min(100, 100 - weekly.usedPercent))
            let percent = remaining.formatted(.percent.scale(1).locale(UsageLocale.current))
            return String(localized: "剩余 \(percent)")
        case .credits: return codex.credits?.formattedBalance ?? "—"
        case .unknown: return "—"
        }
    }
}
