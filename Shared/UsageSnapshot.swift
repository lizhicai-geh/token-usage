import Darwin
import Foundation

struct UsageSnapshot: Codable, Sendable {
    let usage: AccountUsage
    let fetchedAt: Date
    var localToday: AccountUsage.DailyBucket? = nil

    static let widgetKind = "dev.codextoken.usage"
    static let refreshInterval: TimeInterval = 15 * 60

    private static var file: URL? {
        // Foundation returns the extension's sandbox home. Resolve the login
        // home so both processes address the same file.
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var storage = [CChar](repeating: 0, count: 16_384)
        return storage.withUnsafeMutableBufferPointer { buffer in
            guard getpwuid_r(getuid(), &record, buffer.baseAddress, buffer.count, &result) == 0,
                  result != nil, let directory = record.pw_dir else { return nil }
            return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
                .appending(path: "Library/Application Support/CodexTokenWidget/usage.json")
        }
    }

    static func load() -> Self? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        guard let file = Self.file else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
}
