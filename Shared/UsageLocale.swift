import Foundation

enum UsageLocale {
    static let current: Locale = {
        // Match the bundle's language while respecting the system's regional formats.
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        var components = Locale.Components(identifier: language)
        components.region = Locale.current.region
        return Locale(components: components)
    }()

    static func dateStyle(calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: current, calendar: calendar, timeZone: calendar.timeZone)
    }
}
