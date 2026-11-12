import Darwin
import Foundation

enum AppServerError: LocalizedError, Equatable {
    case cliNotFound
    case disconnected
    case invalidResponse
    case timeout
    case rpc(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound: return String(localized: "找不到 Codex CLI。请安装 Codex CLI 或 ChatGPT 桌面 App。")
        case .disconnected: return String(localized: "Codex App Server 已断开。请检查 Codex CLI 是否能正常启动。")
        case .invalidResponse: return String(localized: "Codex App Server 返回了无法识别的用量数据。")
        case .timeout: return String(localized: "读取 Codex 用量超时，请稍后重试。")
        case .rpc(-32601, _): return String(localized: "当前 Codex CLI 不支持账户用量接口，请更新 Codex。")
        case .rpc(let code, let message): return String(localized: "Codex App Server（\(code)）\n\(message)")
        }
    }
}

struct AppServerClient: Sendable {
    let executable: URL
    var environment = ProcessInfo.processInfo.environment
    var timeout: TimeInterval = 20

    static func installed() throws -> Self {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        let candidates = [environment["CODEX_TOKEN_WIDGET_CLI"]].compactMap { $0 } + path + [
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        ]
        guard let executable = candidates.first(where: {
            $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw AppServerError.cliNotFound }
        return Self(executable: URL(fileURLWithPath: executable))
    }

    func readUsage() throws -> AccountUsage {
        try read(method: "account/usage/read")
    }

    func readRateLimits() throws -> AccountRateLimits {
        try read(method: "account/rateLimits/read")
    }

    private func read<Result: Decodable>(method: String) throws -> Result {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let writer = input.fileHandleForWriting
        let reader = output.fileHandleForReading
        defer {
            try? writer.close()
            try? reader.close()
            if process.isRunning { process.terminate() }
        }
        // A server that exits between the handshake and the request should fail the write.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        var rpc = StdioRPC(writer: writer, readFD: reader.fileDescriptor, deadline: .now() + timeout)
        try rpc.send(#"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex_token_widget","title":"Codex Token Widget","version":"1.0.0"}}}"#)
        let _: StdioRPC.Initialized = try rpc.response(id: 1)
        try rpc.send(#"{"method":"initialized"}"#)
        try rpc.send("{\"id\":2,\"method\":\"\(method)\"}")
        return try rpc.response(id: 2)
    }
}

private struct StdioRPC {
    struct Initialized: Decodable {}

    private struct Envelope: Decodable {
        let id: Int?

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            id = try? fields.decode(Int.self, forKey: .id)
        }

        enum CodingKeys: String, CodingKey { case id }
    }

    private struct Response<Result: Decodable>: Decodable {
        struct Failure: Decodable {
            let code: Int
            let message: String
        }

        let result: Result?
        let error: Failure?
    }

    let writer: FileHandle
    let readFD: Int32
    let deadline: DispatchTime
    private var buffer = Data()

    init(writer: FileHandle, readFD: Int32, deadline: DispatchTime) {
        self.writer = writer
        self.readFD = readFD
        self.deadline = deadline
    }

    func send(_ message: String) throws {
        do {
            try writer.write(contentsOf: Data((message + "\n").utf8))
        } catch {
            throw AppServerError.disconnected
        }
    }

    mutating func response<Result: Decodable>(id: Int) throws -> Result {
        let decoder = JSONDecoder()
        while true {
            let line = try nextLine()
            guard (try? decoder.decode(Envelope.self, from: line))?.id == id else { continue }
            guard let reply = try? decoder.decode(Response<Result>.self, from: line) else {
                throw AppServerError.invalidResponse
            }
            if let error = reply.error {
                throw AppServerError.rpc(code: error.code, message: error.message)
            }
            guard let result = reply.result else { throw AppServerError.invalidResponse }
            return result
        }
    }

    private mutating func nextLine() throws -> Data {
        while true {
            guard DispatchTime.now() < deadline else { throw AppServerError.timeout }
            if let end = buffer.firstIndex(of: 0x0a) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                return line
            }
            guard buffer.count < 4 * 1_024 * 1_024 else { throw AppServerError.invalidResponse }
            try readChunk()
        }
    }

    private mutating func readChunk() throws {
        let remaining = deadline.uptimeNanoseconds - min(deadline.uptimeNanoseconds, DispatchTime.now().uptimeNanoseconds)
        let milliseconds = Int32(clamping: (remaining + 999_999) / 1_000_000)
        var descriptor = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, milliseconds)
        if ready == 0 { throw AppServerError.timeout }
        if ready < 0 && errno == EINTR { return }
        guard ready > 0 else { throw AppServerError.disconnected }

        var bytes = [UInt8](repeating: 0, count: 8_192)
        let count = Darwin.read(readFD, &bytes, bytes.count)
        if count < 0 && errno == EINTR { return }
        guard count > 0 else { throw AppServerError.disconnected }
        buffer.append(contentsOf: bytes.prefix(count))
    }
}
