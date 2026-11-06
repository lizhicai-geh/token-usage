import SwiftUI

struct LCDPanel: View {
    let snapshot: UsageSnapshot?
    let date: Date
    var isPreview = false

    private static let side: CGFloat = 346
    private static let ink = Color(red: 0.065, green: 0.080, blue: 0.069)
    private static let divider = ink.opacity(0.28)
    private static let screenSize = CGSize(width: 290, height: 295)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height) / Self.side
            face
                .frame(width: Self.side, height: Self.side)
                .scaleEffect(scale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .environment(\.colorScheme, .light)
    }

    private var face: some View {
        let calendar = Calendar.localGregorian
        let activity = ActivityCalendar(usage: snapshot?.usage, localToday: snapshot?.localToday, date: date, calendar: calendar)
        let day = calendar.usageDateKey(for: date).suffix(5).replacingOccurrences(of: "-", with: "/")
        let readout = TokenFormat.lcd(activity.todayTokens)

        return ZStack(alignment: .topLeading) {
            bezel
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)  今日").font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("Codex · 账户 · API").font(.system(size: 8, weight: .medium))
            }
            .offset(x: 40, y: 36)

            SegmentReadout(readout: readout)
                .frame(width: 246, height: 60)
                .position(x: 170, y: 111)
                .accessibilityLabel(activity.todayIsLocal ? "今日本机 Token 数" : "今日 Token 数")
                .accessibilityValue(activity.todayTokens.map(String.init) ?? "暂无数据")

            Text(activity.todayIsLocal ? "今日 TOKENS · 本机" : "今日 TOKENS")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .position(x: 173, y: 153)
                .accessibilityHidden(true)

            rule(at: 163)
            Text("Token 活动")
                .font(.system(size: 10, weight: .semibold))
                .offset(x: 38, y: 169)

            ActivityGrid(activity: activity)
                .frame(width: 273, height: 76)
                .offset(x: 37, y: 185)

            rule(at: 267)
            summary.offset(x: 35, y: 275)
            rule(at: 305)

            Text(footer)
                .font(.system(size: 6.5, weight: .medium))
                .position(x: 173, y: 313)
        }
        .foregroundStyle(Self.ink)
    }

    private var bezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 35)
                .fill(.linearGradient(colors: [Color(white: 0.93), Color(white: 0.982), Color(white: 0.91)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 35)
                        .strokeBorder(.white.opacity(0.75), lineWidth: 1)
                }
                .frame(width: 328, height: 331)
                .position(x: 173, y: 171.5)

            RoundedRectangle(cornerRadius: 18)
                .fill(.linearGradient(colors: [Color(white: 0.76), .white], startPoint: .top, endPoint: .bottom))
                .frame(width: 303, height: 306)
                .position(x: 173, y: 173)

            RoundedRectangle(cornerRadius: 12)
                .fill(
                    .linearGradient(
                        colors: [Color(red: 0.56, green: 0.58, blue: 0.56), Color(red: 0.60, green: 0.61, blue: 0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Canvas { context, size in
                        var lines = Path()
                        for row in 0..<Int(size.height / 2) {
                            lines.addRect(CGRect(x: 0, y: CGFloat(row) * 2, width: size.width, height: 0.45))
                        }
                        context.fill(lines, with: .color(.black.opacity(0.026)))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            .linearGradient(colors: [.black.opacity(0.50), .black.opacity(0.26), .white.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.3
                        )
                }
                .frame(width: Self.screenSize.width, height: Self.screenSize.height)
                .position(x: 172, y: 173)
        }
        .accessibilityHidden(true)
    }

    private func rule(at y: CGFloat) -> some View {
        Rectangle()
            .fill(Self.divider)
            .frame(width: 275, height: 0.65)
            .position(x: 173, y: y)
            .accessibilityHidden(true)
    }

    private var summary: some View {
        let stats = snapshot?.usage.summary
        return HStack(spacing: 0) {
            metric("累计 Token 数", TokenFormat.count(stats?.lifetimeTokens))
            metric("Token 使用峰值", TokenFormat.count(stats?.peakDailyTokens), divided: true)
            metric("最长任务用时", TokenFormat.duration(stats?.longestRunningTurnSec), width: 69, divided: true)
            metric("最长连续天数", TokenFormat.days(stats?.longestStreakDays), divided: true)
            metric("当前连续天数", TokenFormat.days(stats?.currentStreakDays), divided: true)
        }
    }

    private func metric(_ label: String, _ value: String, width: CGFloat = 51.5, divided: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 6.4, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
        .frame(width: width, height: 26)
        .overlay(alignment: .leading) {
            if divided { Rectangle().fill(Self.divider).frame(width: 0.65, height: 24) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var footer: String {
        if isPreview { return "已更新 15:20 · 预览数据" }
        guard let snapshot else { return "打开 Codex Token 刷新" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: snapshot.fetchedAt)
        let stale = date.timeIntervalSince(snapshot.fetchedAt) > 3 * UsageSnapshot.refreshInterval
        return "已更新 \(time) · \(stale ? "缓存数据" : "账户用量")"
    }

    private struct ActivityGrid: View {
        let activity: ActivityCalendar

        var body: some View {
            Canvas { context, size in
                let columnWidth = size.width / CGFloat(ActivityCalendar.weekCount)
                for (column, week) in activity.weeks.enumerated() {
                    let x = CGFloat(column) * columnWidth
                    if let month = week.month {
                        let label = Text("\(month)月").font(.system(size: 7, weight: .medium)).foregroundStyle(ink)
                        context.draw(label, at: CGPoint(x: x + 2, y: 7), anchor: .leading)
                    }
                    for (row, day) in week.days.enumerated() where !day.isFuture {
                        let rect = CGRect(x: x, y: 16 + CGFloat(row) * 8.75, width: columnWidth - 2.15, height: 7.15)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.45), with: .color(ink.opacity(opacity(day.tokens))))
                    }
                }
            }
            .accessibilityLabel("最近 \(ActivityCalendar.weekCount) 周 Token 活动")
        }

        private func opacity(_ tokens: UInt64?) -> Double {
            guard let tokens, tokens > 0, activity.peak > 0 else { return 0.13 }
            switch Double(tokens) / Double(activity.peak) {
            case ..<0.08: return 0.29
            case ..<0.25: return 0.46
            case ..<0.60: return 0.62
            default: return 0.82
            }
        }
    }

    private struct SegmentReadout: View {
        let readout: TokenFormat.Readout

        // Top, upper right, lower right, bottom, lower left, upper left, middle.
        private static let masks: [Character: UInt8] = [
            "0": 0x3f, "1": 0x06, "2": 0x5b, "3": 0x4f, "4": 0x66, "5": 0x6d,
            "6": 0x7d, "7": 0x07, "8": 0x7f, "9": 0x6f, "—": 0x40
        ]

        private static let segments: [[CGPoint]] = [
            [(5, 0), (27, 0), (31, 4), (27, 6), (5, 6), (1, 4)],
            [(29, 8), (33, 3), (33, 26), (29, 29), (27, 26), (27, 10)],
            [(29, 30), (33, 33), (33, 55), (29, 52), (27, 49), (27, 33)],
            [(5, 53), (27, 53), (31, 56), (27, 59), (5, 59), (1, 56)],
            [(3, 30), (6, 33), (6, 49), (4, 53), (0, 55), (0, 33)],
            [(0, 4), (4, 7), (6, 10), (6, 26), (3, 29), (0, 26)],
            [(5, 27), (27, 27), (30, 30), (27, 33), (5, 33), (2, 30)]
        ].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }

        var body: some View {
            Canvas { context, size in
                let digitWidth: CGFloat = 39
                let pointWidth: CGFloat = 11
                let unitWidth: CGFloat = readout.unit.isEmpty ? 0 : 21
                let numberWidth = readout.digits.reduce(CGFloat(0)) { $0 + ($1 == "." ? pointWidth : digitWidth) } - 6
                var x = (size.width - numberWidth - unitWidth) / 2

                for digit in readout.digits {
                    if digit == "." {
                        context.fill(Path(roundedRect: CGRect(x: x, y: 52, width: 6, height: 6), cornerRadius: 0.9), with: .color(ink))
                        x += pointWidth
                    } else {
                        draw(digit, at: x, in: context)
                        x += digitWidth
                    }
                }

                if !readout.unit.isEmpty {
                    let unit = Text(readout.unit).font(.system(size: 17, weight: .semibold, design: .monospaced)).foregroundStyle(ink)
                    context.draw(unit, at: CGPoint(x: x, y: 54), anchor: .leading)
                }
            }
        }

        private func draw(_ digit: Character, at x: CGFloat, in context: GraphicsContext) {
            let mask = Self.masks[digit] ?? 0
            for (index, points) in Self.segments.enumerated() {
                let polygon = Path { path in
                    path.addLines(points.map { CGPoint(x: $0.x + x, y: $0.y) })
                    path.closeSubpath()
                }
                let isOn = mask & (1 << index) != 0
                context.fill(polygon, with: .color(ink.opacity(isOn ? 1 : 0.115)))
            }
        }
    }
}
