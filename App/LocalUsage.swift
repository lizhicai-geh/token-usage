import Foundation

enum LocalUsage {
    static var codexHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], path.hasPrefix("/") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    static func readToday(codexHome: URL, date: Date, calendar: Calendar) -> AccountUsage.DailyBucket? {
        let dayStart = calendar.startOfDay(for: date)
        var seen = Set<Reading>()
        var total: UInt64?
        for file in rollouts(in: codexHome, modifiedSince: dayStart) {
            guard let data = try? Data(contentsOf: file) else { continue }
            for reading in readings(in: data, from: dayStart, through: date) {
                guard seen.insert(reading.sample).inserted else { continue }
                let (sum, overflow) = (total ?? 0).addingReportingOverflow(reading.tokens)
                guard !overflow else { return nil }
                total = sum
            }
        }
        return total.map { .init(startDate: calendar.usageDateKey(for: date), tokens: $0) }
    }

    private static func rollouts(in root: URL, modifiedSince date: Date) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        return ["sessions", "archived_sessions"].flatMap { directory -> [URL] in
            let folder = root.appending(path: directory, directoryHint: .isDirectory)
            guard let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
                return []
            }
            return entries.compactMap { entry in
                guard let file = entry as? URL,
                      file.pathExtension == "jsonl",
                      file.lastPathComponent.hasPrefix("rollout-"),
                      let values = try? file.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= date else { return nil }
                return file
            }
        }
    }

    private static func readings(in data: Data, from start: Date, through end: Date) -> [(sample: Reading, tokens: UInt64)] {
        let decoder = JSONDecoder()
        let tokenCountMarker = Array("\"token_count\"".utf8)
        var previousTotal: UInt64?
        return data.withUnsafeBytes { bytes in
            bytes.split(separator: 0x0a).compactMap { line in
                guard line.firstRange(of: tokenCountMarker) != nil,
                      let event = try? decoder.decode(Event.self, from: Data(line)),
                      event.type == "event_msg", event.payload.type == "token_count",
                      let usage = event.payload.info, let timestamp = parseDate(event.timestamp) else { return nil }

                let total = usage.total.totalTokens
                let previous = previousTotal
                previousTotal = total
                guard start <= timestamp, timestamp <= end else { return nil }

                // The log can repeat a cumulative count or reset it when a thread rolls back.
                let last = usage.last?.totalTokens
                let tokens = previous.flatMap { total >= $0 ? total - $0 : nil } ?? last
                return tokens.map { (Reading(timestamp: timestamp, total: total, last: last), $0) }
            }
        }
    }

    private static func parseDate(_ timestamp: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp))
            ?? (try? Date.ISO8601FormatStyle().parse(timestamp))
    }

    private struct Reading: Hashable {
        let timestamp: Date
        let total: UInt64
        let last: UInt64?
    }

    private struct Event: Decodable {
        struct Payload: Decodable {
            struct Usage: Decodable {
                struct Count: Decodable {
                    let totalTokens: UInt64

                    enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
                }

                let total: Count
                let last: Count?

                enum CodingKeys: String, CodingKey {
                    case total = "total_token_usage"
                    case last = "last_token_usage"
                }
            }

            let type: String
            let info: Usage?
        }

        let timestamp: String
        let type: String
        let payload: Payload
    }
}
