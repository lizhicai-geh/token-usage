import Foundation

enum ActivityDayLink {
    private static let scheme = "codextoken"
    private static let host = "activity"
    static let route = "\(scheme)://\(host)/"

    static func url(for date: Date) -> URL? {
        URL(string: route + String(Int(date.timeIntervalSince1970)))
    }

    static func date(from url: URL) -> Date? {
        guard url.scheme == scheme, url.host == host, url.pathComponents.count == 2,
              let seconds = Int(url.lastPathComponent) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
