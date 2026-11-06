import CryptoKit
import Darwin
import Foundation

enum LocalUsage {
    private static var codexHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], path.hasPrefix("/") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    static func readToday() throws -> AccountUsage.DailyBucket? {
        guard let directory = UsageSnapshot.directory else { throw CocoaError(.fileNoSuchFile) }
        return try readToday(
            codexHome: codexHome, indexFile: directory.appending(path: "local-usage-index.json"),
            date: .now, calendar: .localGregorian
        )
    }

    static func readToday(codexHome: URL, indexFile: URL, date: Date, calendar: Calendar) throws -> AccountUsage.DailyBucket? {
        let start = calendar.startOfDay(for: date)
        let home = codexHome.standardizedFileURL.path
        let saved = (try? Data(contentsOf: indexFile)).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
        var index = Index(home: home, start: start)
        if let saved, saved.home == home, saved.start == start {
            index = saved
        }

        for file in rollouts(in: codexHome, modifiedSince: start) {
            try index.readAppends(in: file, through: date)
        }

        if index != saved {
            try FileManager.default.createDirectory(
                at: indexFile.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try JSONEncoder().encode(index).write(to: indexFile, options: .atomic)
        }
        return index.total.map { .init(startDate: calendar.usageDateKey(for: date), tokens: $0) }
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

    private struct Index: Codable, Equatable {
        let home: String
        let start: Date
        var cursors: [String: Cursor] = [:]
        var seen: Set<Reading> = []
        var total: UInt64?

        mutating func readAppends(in file: URL, through end: Date) throws {
            // The file may have moved to the archive since it was enumerated.
            guard let handle = try? FileHandle(forReadingFrom: file) else { return }
            defer { try? handle.close() }
            var attributes = stat()
            guard fstat(handle.fileDescriptor, &attributes) == 0, attributes.st_size >= 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            let key = "\(attributes.st_dev):\(attributes.st_ino)"
            let size = UInt64(attributes.st_size)
            var cursor = cursors[key] ?? Cursor()
            if cursor.offset > size {
                cursor = Cursor()
            } else if try Self.fingerprint(handle, before: cursor.offset) != cursor.fingerprint {
                cursor = Cursor()
            }
            guard cursor.offset < size else { return }
            try handle.seek(toOffset: cursor.offset)
            let data = try handle.read(upToCount: Int(size - cursor.offset)) ?? Data()
            try consume(data, through: end, cursor: &cursor)
            cursor.fingerprint = try Self.fingerprint(handle, before: cursor.offset)
            cursors[key] = cursor
        }

        private mutating func consume(_ data: Data, through end: Date, cursor: inout Cursor) throws {
            let decoder = JSONDecoder()
            let marker = Array("\"token_count\"".utf8)
            try data.withUnsafeBytes { bytes in
                // Keep an unfinished last line pending until Codex writes its newline.
                for line in bytes.split(separator: 0x0a, omittingEmptySubsequences: false).dropLast() {
                    if line.firstRange(of: marker) != nil,
                       let reading = Reading.decode(Data(line), with: decoder) {
                        guard reading.timestamp <= end else { break }
                        if reading.timestamp >= start {
                            try count(reading, previous: cursor.previousTotal)
                        }
                        cursor.previousTotal = reading.total
                    }
                    cursor.offset += UInt64(line.count) + 1
                }
            }
        }

        private mutating func count(_ reading: Reading, previous: UInt64?) throws {
            // Cumulative values can repeat or reset after a rollback.
            let tokens = previous.flatMap { reading.total >= $0 ? reading.total - $0 : nil } ?? reading.last
            guard let tokens, seen.insert(reading).inserted else { return }
            let (sum, overflow) = (total ?? 0).addingReportingOverflow(tokens)
            guard !overflow else { throw CocoaError(.fileReadCorruptFile) }
            total = sum
        }

        private static func fingerprint(_ file: FileHandle, before offset: UInt64) throws -> Data? {
            guard offset > 0 else { return nil }
            let length = min(offset, 128)
            try file.seek(toOffset: offset - length)
            guard let bytes = try file.read(upToCount: Int(length)), bytes.count == Int(length) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return Data(SHA256.hash(data: bytes))
        }
    }

    private struct Cursor: Codable, Equatable {
        var offset: UInt64 = 0
        var previousTotal: UInt64?
        var fingerprint: Data?
    }

    private struct Reading: Codable, Hashable {
        let timestamp: Date
        let total: UInt64
        let last: UInt64?

        static func decode(_ line: Data, with decoder: JSONDecoder) -> Self? {
            guard let event = try? decoder.decode(Event.self, from: line),
                  event.type == "event_msg", event.payload.type == "token_count",
                  let usage = event.payload.info else { return nil }
            let timestamp = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(event.timestamp))
                ?? (try? Date.ISO8601FormatStyle().parse(event.timestamp))
            return timestamp.map { Reading(timestamp: $0, total: usage.total.totalTokens, last: usage.last?.totalTokens) }
        }
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
