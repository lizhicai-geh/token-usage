import Foundation

@main
enum UsageTests {
    static func main() throws {
        if CommandLine.arguments.dropFirst().first == "app-server" {
            try serve()
            return
        }

        let data = Data(Self.payload.utf8)
        let usage = try JSONDecoder().decode(AccountUsage.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try require(TimeZone(identifier: "Asia/Shanghai"))
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12)))
        let activity = ActivityCalendar(usage: usage, date: date, calendar: calendar)

        try check(usage.summary.lifetimeTokens == 36_320_000_000, "Token 总量支持 64 位整数")
        try check(usage.summary.currentStreakDays == nil, "空值保留")
        try check(activity.todayTokens == 128_600, "今日 Token 按日历日期匹配")
        try check(activity.weeks.count == 27, "热力图为 27 周")
        try check(activity.weeks.last?.days.map(\.tokens) == [nil, 0, 128_600, nil, nil, nil, nil], "保留明确的零，过滤未来日期")
        try check(activity.weeks.last?.days.map(\.isFuture) == [false, false, false, true, true, true, true], "周一开头，未来日期不绘制")
        try check(activity.weeks.dropLast().last?.month == 11, "月初位于首个可见周时标注")
        let nextDay = try require(calendar.date(byAdding: .day, value: 1, to: date))
        try check(ActivityCalendar(usage: usage, date: nextDay, calendar: calendar).todayTokens == 900_000, "跨天读取新日期")
        let empty = try JSONDecoder().decode(AccountUsage.self, from: Data(#"{"summary":{},"dailyUsageBuckets":null}"#.utf8))
        try check(ActivityCalendar(usage: empty, date: date, calendar: calendar).todayTokens == nil, "缺失数据不显示成零")
        try check(TokenFormat.lcd(128_600) == .init(digits: "128.6", unit: "K"), "主显示匹配参考格式")
        try check(TokenFormat.lcd(999_999) == .init(digits: "1.0", unit: "M"), "四舍五入后进位")
        try check(TokenFormat.count(36_320_000_000) == "363.2亿", "累计量使用中文单位")
        try check(TokenFormat.duration(80_640) == "22 小时 24 分", "最长任务按时分显示")

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let client = AppServerClient(executable: executable)
        let read = try client.readUsage()
        try check(read == usage, "完整 RPC 握手并跳过异步通知")
        try expectFailure("invalid", executable: executable, .invalidResponse)
        try expectFailure("error", executable: executable, .rpc(code: -32601, message: "Method not found"))
        try expectFailure("timeout", executable: executable, .timeout)
        print("用量、热力图、格式和 App Server RPC 测试通过")
    }

    private static func expectFailure(_ mode: String, executable: URL, _ expected: AppServerError) throws {
        let client = AppServerClient(executable: executable, environment: ["TEST_SERVER_MODE": mode], timeout: 0.6)
        do {
            _ = try client.readUsage()
            throw Failure(message: "预期 RPC 错误：\(expected)")
        } catch let error as AppServerError {
            try check(error == expected, "RPC 错误：\(error)")
        }
    }

    private static func serve() throws {
        let initialize = try request()
        try check(initialize["id"] as? Int == 1 && initialize["method"] as? String == "initialize", "先初始化")
        reply(#"{"method":"test/notification","params":{}}"#)
        reply(#"{"id":1,"result":{}}"#)
        let initialized = try request()
        try check(initialized["id"] == nil && initialized["method"] as? String == "initialized", "发送初始化完成通知")
        let read = try request()
        try check(read["id"] as? Int == 2 && read["method"] as? String == "account/usage/read" && read["params"] == nil, "读取账户用量")
        switch ProcessInfo.processInfo.environment["TEST_SERVER_MODE"] {
        case "invalid": reply(#"{"id":2,"result":{"dailyUsageBuckets":[]}}"#)
        case "error": reply(#"{"id":2,"error":{"code":-32601,"message":"Method not found"}}"#)
        case "timeout": Thread.sleep(forTimeInterval: 5)
        default:
            reply(#"{"id":77,"result":{}}"#)
            reply("{\"id\":2,\"result\":\(Self.payload)}")
        }
    }

    private static func request() throws -> [String: Any] {
        let line = try require(readLine())
        return try require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    private static func reply(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure(message: "缺少测试输入") }
        return value
    }

    private struct Failure: Error {
        let message: String
    }

    private static let payload = #"{"summary":{"lifetimeTokens":36320000000,"peakDailyTokens":5390000000,"longestRunningTurnSec":80640,"currentStreakDays":null,"longestStreakDays":12},"dailyUsageBuckets":[{"startDate":"2026-11-05","tokens":900000},{"startDate":"2026-11-04","tokens":128600},{"startDate":"2026-11-03","tokens":0}]}"#
}
