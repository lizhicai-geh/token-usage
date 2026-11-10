import Foundation

@main
enum UsageTests {
    @MainActor
    static func main() async throws {
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
        try checkActivityHistory(usage: usage, empty: empty, date: date, calendar: calendar)
        try checkLocalUsage(account: usage, emptyAccount: empty, date: date, calendar: calendar)
        try check(TokenFormat.lcd(128_600) == .init(digits: "128.6", unit: "K"), "主显示匹配参考格式")
        try check(TokenFormat.lcd(999_999) == .init(digits: "1.0", unit: "M"), "四舍五入后进位")
        try check(TokenFormat.count(36_320_000_000) == "363.2亿", "累计量使用中文单位")
        try check(TokenFormat.duration(80_640) == "22 小时 24 分", "最长任务按时分显示")
        try checkRateLimits()

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let client = AppServerClient(executable: executable)
        let read = try client.readUsage()
        try check(read == usage, "完整 RPC 握手并跳过异步通知")
        let limits = try client.readRateLimits()
        try check(limits.source == .weekly && limits.value == "剩余 44%", "额度接口完成握手并读取周额度")
        try expectFailure("invalid", executable: executable, .invalidResponse)
        try expectFailure("error", executable: executable, .rpc(code: -32601, message: "Method not found"))
        try expectFailure("timeout", executable: executable, .timeout)
        try await checkIndependentRefresh(account: usage)
        try await checkRateLimitsRefresh(account: usage)
        try await checkRateLimitsPublishFailure(account: usage)
        try await checkManualWidgetReload(account: usage)
        print("用量、热力图、额度切换、独立刷新和 App Server RPC 测试通过")
    }

    private static func checkActivityHistory(usage: AccountUsage, empty: AccountUsage, date: Date, calendar: Calendar) throws {
        let historical = AccountUsage(summary: usage.summary, dailyUsageBuckets: (usage.dailyUsageBuckets ?? []) + [
            .init(startDate: "2024-12-31", tokens: 0),
            .init(startDate: "2025-01-01", tokens: 5_000_000),
            .init(startDate: "2020-02-31", tokens: 99_000_000),
            .init(startDate: "2030-01-01", tokens: 99_000_000)
        ])
        let history = ActivityCalendar(usage: historical, date: date, calendar: calendar, includeHistory: true)
        let days = history.weeks.flatMap(\.days)
        try check(history.weeks.count > 27, "App 热图包含超过 27 周的历史")
        try check(days.first.map { calendar.usageDateKey(for: $0.date) } == "2024-12-30", "最早历史周从周一开始，跨年不丢失日期")
        try check(days.first { calendar.usageDateKey(for: $0.date) == "2024-12-31" }?.tokens == 0, "历史记录保留明确的零")
        try check(history.peak == 5_000_000, "历史颜色范围包含旧记录，排除未来和无效日期")
        try check(history.todayTokens == 128_600 && history.weeks.last?.days.map(\.tokens) == ActivityCalendar(usage: usage, date: date, calendar: calendar).weeks.last?.days.map(\.tokens), "扩展历史不影响今日数据和最新一周")
        try check(ActivityCalendar(usage: historical, date: date, calendar: calendar).weeks.count == 27, "桌面小组件仍只展示最近 27 周")
        try check(ActivityCalendar(usage: empty, date: date, calendar: calendar, includeHistory: true).weeks.count == 27, "缺失历史时保留最近 27 周")
        try check(calendar.usageDate(from: "2026-02-30") == nil && calendar.usageDate(from: "2026-2-03") == nil, "无效及非规范日期不能扩展历史范围")
        try check(calendar.usageDate(from: "2024-02-29").map { calendar.usageDateKey(for: $0) } == "2024-02-29", "闰日可以用于历史定位")
    }

    private static func checkRateLimits() throws {
        var limits = try JSONDecoder().decode(AccountRateLimits.self, from: Data(rateLimitsPayload.utf8))
        try check(limits.source == .weekly && limits.label == "周额度" && limits.value == "剩余 44%", "有积分余额但仍在使用套餐时显示周额度")
        limits.ordinaryUsageAllowed = false
        try check(limits.source == .credits && limits.label == "积分" && limits.value == "9,702", "服务端禁止套餐用量时显示积分余额")
        limits.rateLimits.secondary?.usedPercent = 100
        limits.ordinaryUsageAllowed = true
        try check(limits.source == .weekly && limits.value == "剩余 0%", "服务端套餐状态优先于旧窗口百分比")
        limits.ordinaryUsageAllowed = nil
        try check(limits.source == .credits, "旧版服务端在周额度耗尽时切换积分")
        limits.rateLimits.secondary?.usedPercent = 56
        limits.rateLimits.primary = .init(usedPercent: 100, windowDurationMins: 300)
        try check(limits.source == .credits, "短期额度耗尽但周额度尚有剩余时也显示积分")
        limits.rateLimits.primary?.usedPercent = 10
        try check(limits.source == .weekly, "套餐额度恢复后切回周额度")
        limits.rateLimitsByLimitId = ["codex": .init(primary: .init(usedPercent: 20, windowDurationMins: 10_080))]
        try check(limits.value == "剩余 80%", "优先选择 codex 桶，按窗口长度识别周额度")
        limits.rateLimitsByLimitId = nil
        limits.ordinaryUsageAllowed = false
        limits.rateLimits.credits?.balance = "9702.25"
        try check(limits.value == "9,702.25", "积分保留小数并添加千位分隔")
        limits.rateLimits.credits?.unlimited = true
        try check(limits.value == "不限量", "不限量积分不显示伪造余额")
        limits.rateLimits.credits = .init(hasCredits: false, unlimited: false)
        try check(limits.value == "0", "明确无积分时显示零")
        limits.rateLimits.credits = .init(hasCredits: true, unlimited: false)
        try check(limits.value == "—", "积分余额缺失时保留未知状态")
        limits.rateLimits.credits = nil
        try check(limits.source == .unknown && limits.value == "—", "额度来源无法判断时不误报周额度")

        let legacySnapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(#"{"accountUnavailable":false}"#.utf8))
        try check(legacySnapshot.rateLimits == nil, "旧版快照无需迁移即可读取")
        let snapshot = UsageSnapshot(rateLimits: limits, rateLimitsFetchedAt: .now)
        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))
        try check(restored.rateLimits == limits, "小组件快照保留额度与来源状态")
    }

    private static func checkLocalUsage(account: AccountUsage, emptyAccount: AccountUsage, date: Date, calendar: Calendar) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions/2026/11/03")
        let archive = root.appending(path: "archived_sessions")
        for folder in [sessions, archive] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let samples = [
            tokenEvent("2026-11-03T15:59:59Z", total: 1_000, last: 1_000),
            tokenEvent("2026-11-03T16:00:00.123Z", total: 1_120, last: 120),
            tokenEvent("2026-11-03T16:01:00Z", total: 1_120, last: 120),
            tokenEvent("2026-11-03T17:00:00Z", total: 10, last: 10),
            tokenEvent("2026-11-03T17:01:00Z", total: 100, last: 90),
            tokenEvent("2026-11-04T05:00:00Z", total: 500, last: 400)
        ].joined(separator: "\n") + "\n"
        let nextTime = date.addingTimeInterval(7_200)
        let tomorrow = try require(calendar.date(byAdding: .day, value: 1, to: nextTime))
        let liveFile = sessions.appending(path: "rollout-original.jsonl")
        for file in [liveFile, archive.appending(path: "rollout-fork.jsonl")] {
            try Data(samples.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: tomorrow], ofItemAtPath: file.path)
        }

        let index = root.appending(path: "local-index.json")
        let local = try LocalUsage.readToday(codexHome: root, indexFile: index, date: date, calendar: calendar)
        try check(local == .init(startDate: "2026-11-04", tokens: 220), "本机统计跨午夜增量，排除重复、分叉历史和未来事件")
        let resumed = try LocalUsage.readToday(codexHome: root, indexFile: index, date: date, calendar: calendar)
        try check(resumed == local, "重启后读取持久进度不重复计数")
        let event = tokenEvent("2026-11-04T05:30:00Z", total: 560, last: 60) + String(repeating: " ", count: 140_000)
        try append(event, to: liveFile, modifiedAt: tomorrow)
        let partial = try LocalUsage.readToday(codexHome: root, indexFile: index, date: nextTime, calendar: calendar)
        try check(partial?.tokens == 620, "续读已到时的事件，保留尚未换行的尾部")
        try append("\n", to: liveFile, modifiedAt: tomorrow)
        let completed = try LocalUsage.readToday(codexHome: root, indexFile: index, date: nextTime, calendar: calendar)
        try check(completed?.tokens == 680, "下一次读取补齐的长行")
        let archived = archive.appending(path: liveFile.lastPathComponent)
        try FileManager.default.moveItem(at: liveFile, to: archived)
        let afterMove = try LocalUsage.readToday(codexHome: root, indexFile: index, date: nextTime, calendar: calendar)
        try check(afterMove == completed, "归档移动保留读取进度")
        try append(tokenEvent("2026-11-04T16:00:00Z", total: 575, last: 15) + "\n", to: archived, modifiedAt: tomorrow)
        let nextDay = try LocalUsage.readToday(codexHome: root, indexFile: index, date: tomorrow, calendar: calendar)
        try check(nextDay == .init(startDate: "2026-11-05", tokens: 15), "跨午夜从当前累计基线开始新一天")
        let fallback = ActivityCalendar(usage: emptyAccount, localToday: local, date: date, calendar: calendar)
        try check(fallback.todayTokens == 220 && fallback.todayIsLocal, "账户缺当天时显示本机数据")
        let preferred = ActivityCalendar(usage: account, localToday: local, date: date, calendar: calendar)
        try check(preferred.todayTokens == 128_600 && !preferred.todayIsLocal, "账户当天记录优先")
        let previousDay = try require(calendar.date(byAdding: .day, value: -1, to: date))
        let localPreviousDay = AccountUsage.DailyBucket(startDate: "2026-11-03", tokens: 100)
        let zero = ActivityCalendar(usage: account, localToday: localPreviousDay, date: previousDay, calendar: calendar)
        try check(zero.todayTokens == 0 && !zero.todayIsLocal, "账户明确返回的零优先")
        let expired = ActivityCalendar(usage: emptyAccount, localToday: local, date: previousDay, calendar: calendar)
        try check(expired.todayTokens == nil && !expired.todayIsLocal, "其他日期的本机快照不能当作今天")
    }

    @MainActor
    private static func checkIndependentRefresh(account: AccountUsage) async throws {
        let now = Date.now
        let today = Calendar.localGregorian.usageDateKey(for: now)
        let cachedAccount = AccountUsage(summary: account.summary, dailyUsageBuckets: [.init(startDate: today, tokens: 800)])
        let currentAccount = AccountUsage(summary: account.summary, dailyUsageBuckets: [.init(startDate: today, tokens: 900)])
        let gate = AccountGate()
        var saved: UsageSnapshot?
        let controller = UsageController(
            snapshot: UsageSnapshot(usage: cachedAccount, fetchedAt: now.addingTimeInterval(-60)),
            readAccount: { try await gate.read() },
            readLocal: { .init(startDate: today, tokens: 321) },
            readRateLimits: { try JSONDecoder().decode(AccountRateLimits.self, from: Data(rateLimitsPayload.utf8)) },
            publish: { saved = $0 }
        )
        let pending = Task { await controller.refreshAccount() }
        await gate.waitForRequest()
        await controller.refreshRateLimits()
        await controller.refreshLocal()
        try check(saved?.localToday?.tokens == 321 && saved?.usage == cachedAccount, "账户请求挂起时本机数据独立写入，保留历史账户数据")
        try check(saved?.rateLimits?.value == "剩余 44%", "Token 查询挂起不阻塞额度刷新")
        await gate.finish(.failure(AppServerError.timeout))
        await pending.value
        try check(saved?.localToday?.tokens == 321 && saved?.accountUnavailable == true, "账户超时后保留本机数据")
        let duringTimeout = ActivityCalendar(
            usage: saved?.usage, localToday: saved?.localToday, preferLocalToday: saved?.accountUnavailable == true, date: now
        )
        try check(duringTimeout.todayTokens == 321 && duringTimeout.todayIsLocal, "超时时主数字优先使用本机数据")

        let retry = Task { await controller.refreshAccount() }
        await gate.waitForRequest()
        await gate.finish(.success(currentAccount))
        await retry.value
        let updated = try require(saved)
        let displayed = ActivityCalendar(
            usage: updated.usage, localToday: updated.localToday, preferLocalToday: updated.accountUnavailable == true,
            date: now, calendar: .localGregorian
        )
        try check(displayed.todayTokens == 900 && !displayed.todayIsLocal && updated.localToday?.tokens == 321, "账户数据回来自动切换来源")
    }

    @MainActor
    private static func checkRateLimitsRefresh(account: AccountUsage) async throws {
        let limits = try JSONDecoder().decode(AccountRateLimits.self, from: Data(rateLimitsPayload.utf8))
        var saved: UsageSnapshot?
        let controller = UsageController(
            snapshot: UsageSnapshot(usage: account, rateLimits: limits),
            readAccount: { account }, readLocal: { nil },
            readRateLimits: { throw AppServerError.rpc(code: -32601, message: "Method not found") },
            publish: { saved = $0 }
        )
        await controller.refreshRateLimits()
        await controller.refreshAccount()
        try check(saved?.usage == account && saved?.accountUnavailable == false, "额度查询失败不影响 Token 查询")
        try check(saved?.rateLimits == limits && saved?.rateLimitsUnavailable == true, "额度失败保留快照并标记不可用")
        try check(controller.errorMessage?.contains("额度查询失败") == true, "额度失败展示可识别错误")

        let recovered = UsageController(
            snapshot: saved, readAccount: { account }, readLocal: { nil }, readRateLimits: { limits },
            publish: { saved = $0 }
        )
        await recovered.refreshRateLimits()
        try check(saved?.rateLimitsUnavailable == false && recovered.errorMessage == nil, "额度查询恢复后解除不可用状态")
    }

    @MainActor
    private static func checkRateLimitsPublishFailure(account: AccountUsage) async throws {
        var cached = try JSONDecoder().decode(AccountRateLimits.self, from: Data(rateLimitsPayload.utf8))
        let current = cached
        cached.rateLimits.secondary?.usedPercent = 25
        var publishAttempts = 0
        let controller = UsageController(
            snapshot: UsageSnapshot(usage: account, rateLimits: cached, rateLimitsUnavailable: false),
            readAccount: { account }, readLocal: { nil }, readRateLimits: { current },
            publish: { _ in
                publishAttempts += 1
                if publishAttempts == 1 { throw CocoaError(.fileWriteOutOfSpace) }
            }
        )

        await controller.refreshRateLimits()
        try check(publishAttempts == 1, "保存失败时不额外写入额度不可用状态")
        try check(controller.snapshot?.rateLimits == cached && controller.snapshot?.rateLimitsUnavailable == false,
                  "保存失败时保留原快照和额度可用状态")
        try check(controller.errorMessage?.contains("额度保存失败") == true, "区分保存失败和查询失败")
        await controller.refreshRateLimits()
        try check(controller.snapshot?.rateLimits == current && controller.errorMessage == nil, "保存恢复后更新额度并清除错误")
    }

    @MainActor
    private static func checkManualWidgetReload(account: AccountUsage) async throws {
        let limits = try JSONDecoder().decode(AccountRateLimits.self, from: Data(rateLimitsPayload.utf8))
        let gate = AccountGate()
        var saved: UsageSnapshot?
        var reloads: [UsageSnapshot] = []
        let controller = UsageController(
            snapshot: nil,
            readAccount: { try await gate.read() },
            readLocal: { .init(startDate: "2026-11-04", tokens: 321) },
            readRateLimits: { limits },
            publish: { saved = $0 },
            reloadWidget: { if let saved { reloads.append(saved) } }
        )
        let pending = Task { await controller.refresh() }
        await gate.waitForRequest()
        try check(reloads.isEmpty, "手动刷新等待读取完成后再通知小组件")
        await gate.finish(.success(account))
        await pending.value
        try check(reloads.count == 1, "手动刷新只通知小组件一次")
        try check(reloads.first?.usage == account && reloads.first?.localToday?.tokens == 321 &&
                  reloads.first?.rateLimits == limits, "通知小组件时三类数据均已保存")
    }

    private actor AccountGate {
        private var reply: CheckedContinuation<AccountUsage, any Error>?
        private var started: CheckedContinuation<Void, Never>?

        func read() async throws -> AccountUsage {
            try await withCheckedThrowingContinuation { continuation in
                reply = continuation
                started?.resume()
                started = nil
            }
        }

        func waitForRequest() async {
            guard reply == nil else { return }
            await withCheckedContinuation { started = $0 }
        }

        func finish(_ result: Result<AccountUsage, any Error>) {
            let pending = reply
            reply = nil
            pending?.resume(with: result)
        }
    }

    private static func append(_ text: String, to url: URL, modifiedAt: Date) throws {
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: Data(text.utf8))
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }

    private static func tokenEvent(_ timestamp: String, total: UInt64, last: UInt64) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total)},"last_token_usage":{"total_tokens":\(last)}}}}
        """
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
        let method = read["method"] as? String
        try check(read["id"] as? Int == 2 && ["account/usage/read", "account/rateLimits/read"].contains(method) && read["params"] == nil, "读取账户用量或额度")
        switch ProcessInfo.processInfo.environment["TEST_SERVER_MODE"] {
        case "invalid": reply(#"{"id":2,"result":{"dailyUsageBuckets":[]}}"#)
        case "error": reply(#"{"id":2,"error":{"code":-32601,"message":"Method not found"}}"#)
        case "timeout": Thread.sleep(forTimeInterval: 5)
        default:
            reply(#"{"id":77,"result":{}}"#)
            reply("{\"id\":2,\"result\":\(method == "account/rateLimits/read" ? Self.rateLimitsPayload : Self.payload)}")
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

    private static let rateLimitsPayload = #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300},"secondary":{"usedPercent":56,"windowDurationMins":10080},"credits":{"hasCredits":true,"unlimited":false,"balance":"9702"}},"ordinaryUsageAllowed":true}"#

    private static let payload = #"{"summary":{"lifetimeTokens":36320000000,"peakDailyTokens":5390000000,"longestRunningTurnSec":80640,"currentStreakDays":null,"longestStreakDays":12},"dailyUsageBuckets":[{"startDate":"2026-11-05","tokens":900000},{"startDate":"2026-11-04","tokens":128600},{"startDate":"2026-11-03","tokens":0}]}"#
}
