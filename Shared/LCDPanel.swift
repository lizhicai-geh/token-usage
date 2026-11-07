import SwiftUI

struct LCDPanel: View {
    let snapshot: UsageSnapshot?
    let date: Date
    var isPreview = false
    var activityInteraction: ActivityGrid.Interaction = .none
    @State private var isHoveringAllowance = false

    private static let side: CGFloat = 346
    private static let ink = Color(red: 0.065, green: 0.080, blue: 0.069)
    private static let divider = ink.opacity(0.28)
    private static let screenSize = CGSize(width: 290, height: 290)
    private static let contentFrame = CGRect(x: 28, y: 28, width: screenSize.width, height: screenSize.height)
        .insetBy(dx: 12, dy: 12)

    private var includesActivityHistory: Bool {
        if case .hover = activityInteraction { return true }
        return false
    }

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
        let activity = ActivityCalendar(
            usage: snapshot?.usage, localToday: snapshot?.localToday, preferLocalToday: snapshot?.accountUnavailable == true,
            date: date, calendar: calendar, includeHistory: includesActivityHistory
        )
        let day = calendar.usageDateKey(for: date).suffix(5).replacingOccurrences(of: "-", with: "/")
        let readout = TokenFormat.lcd(activity.todayTokens)

        return ZStack(alignment: .topLeading) {
            bezel
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 8, weight: .medium))
            }
            .offset(x: Self.contentFrame.minX, y: Self.contentFrame.minY)

            allowance
                .frame(width: 34, height: 34)
                .position(x: Self.contentFrame.maxX - 11.5, y: Self.contentFrame.minY + 11.5)
                .zIndex(1)

            SegmentReadout(readout: readout)
                .frame(width: 246, height: 60)
                .position(x: 170, y: 113)
                .accessibilityLabel(todayLabel(activity))
                .accessibilityValue(activity.todayTokens.map(String.init) ?? "暂无数据")

            Text(todayLabel(activity))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .position(x: 173, y: 155)
                .accessibilityHidden(true)

            rule(at: 167)
            HStack {
                Text("Token 活动")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                if includesActivityHistory && activity.weeks.count > ActivityCalendar.weekCount {
                    Text("左右滑动")
                        .font(.system(size: 7))
                        .foregroundStyle(Self.ink.opacity(0.6))
                }
            }
                .frame(width: Self.contentFrame.width)
                .offset(x: Self.contentFrame.minX, y: 173)

            ActivityGrid(activity: activity, calendar: calendar, ink: Self.ink, interaction: activityInteraction)
                .offset(x: Self.contentFrame.minX, y: 189)

            rule(at: 271)
            summary.offset(x: Self.contentFrame.minX, y: Self.contentFrame.maxY - 26)
        }
        .foregroundStyle(Self.ink)
    }

    private var allowance: some View {
        allowanceRing
            .onHover { isHoveringAllowance = $0 }
            .overlay(alignment: .trailing) {
                if isHoveringAllowance {
                    allowanceTooltip
                        .fixedSize()
                        .offset(x: -42)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("当前使用\(snapshot?.rateLimits?.label ?? "额度")")
            .accessibilityValue(allowanceDescription)
    }

    private var allowanceRing: some View {
        let limits = snapshot?.rateLimits
        let available = snapshot?.rateLimitsUnavailable != true
        let progress: Double = {
            guard available, let limits else { return 0 }
            switch limits.source {
            case .weekly: return Double(max(0, min(100, 100 - (limits.codex.weekly?.usedPercent ?? 100)))) / 100
            case .credits: return limits.codex.credits?.hasCredits == true || limits.codex.credits?.unlimited == true ? 1 : 0
            case .unknown: return 0
            }
        }()

        return ZStack {
            Circle().stroke(Self.ink.opacity(0.18), lineWidth: 2)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Self.ink.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if limits?.source == .credits {
                CoinStack()
                    .stroke(Self.ink.opacity(available ? 0.7 : 0.18),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 14)
            } else {
                RoundedRectangle(cornerRadius: 1.3)
                    .fill(Self.ink.opacity(available ? 0.55 : 0.18))
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
            }
        }
        .frame(width: 23, height: 23)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private struct CoinStack: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addEllipse(in: CGRect(x: 1, y: 1, width: 10, height: 4))
            path.move(to: CGPoint(x: 1, y: 3))
            path.addLine(to: CGPoint(x: 1, y: 10.5))
            path.addCurve(to: CGPoint(x: 11, y: 10.5),
                          control1: CGPoint(x: 1, y: 13.5), control2: CGPoint(x: 11, y: 13.5))
            path.addLine(to: CGPoint(x: 11, y: 3))
            for y: CGFloat in [5.5, 8] {
                path.move(to: CGPoint(x: 1, y: y))
                path.addCurve(to: CGPoint(x: 11, y: y),
                              control1: CGPoint(x: 1, y: y + 3), control2: CGPoint(x: 11, y: y + 3))
            }
            return path.applying(CGAffineTransform(scaleX: rect.width / 12, y: rect.height / 14))
        }
    }

    private var allowanceDescription: String {
        let limits = snapshot?.rateLimits
        let unavailable = snapshot?.rateLimitsUnavailable == true
        let stale = snapshot?.rateLimitsFetchedAt.map { date.timeIntervalSince($0) > 3 * UsageSnapshot.refreshInterval } ?? false
        if unavailable { return "额度暂时无法读取" }
        guard let limits else { return "额度暂无数据" }
        let title = limits.source == .weekly ? "每周" : limits.label
        return "\(title) · \(limits.value)\(stale ? " · 缓存数据" : "")"
    }

    private var allowanceTooltip: some View {
        let limits = snapshot?.rateLimits
        let title = limits?.source == .weekly ? "每周" : (limits?.label ?? "额度")
        let unavailable = snapshot?.rateLimitsUnavailable == true
        let stale = snapshot?.rateLimitsFetchedAt.map { date.timeIntervalSince($0) > 3 * UsageSnapshot.refreshInterval } ?? false
        let value = unavailable ? "暂不可用" : (limits?.value ?? "暂无数据")
        let bubble = RoundedRectangle(cornerRadius: 12)

        return HStack(spacing: 0) {
            Text(title).fontWeight(.semibold)
            Text(" · \(value)\(stale && !unavailable ? "（缓存）" : "")").fontWeight(.regular)
        }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(white: 0.17), in: bubble)
            .overlay { bubble.strokeBorder(Color(white: 0.23), lineWidth: 1) }
    }

    private var bezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 35)
                .fill(.linearGradient(colors: [Color(white: 0.93), Color(white: 0.982), Color(white: 0.91)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 35)
                        .strokeBorder(.white.opacity(0.75), lineWidth: 1)
                }
                .frame(width: 328, height: 328)
                .position(x: 173, y: 173)

            RoundedRectangle(cornerRadius: 18)
                .fill(.linearGradient(colors: [Color(white: 0.76), .white], startPoint: .top, endPoint: .bottom))
                .frame(width: 303, height: 303)
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
                .position(x: 173, y: 173)
        }
        .accessibilityHidden(true)
    }

    private func rule(at y: CGFloat) -> some View {
        Rectangle()
            .fill(Self.divider)
            .frame(width: Self.contentFrame.width, height: 0.65)
            .position(x: Self.contentFrame.midX, y: y)
            .accessibilityHidden(true)
    }

    private var summary: some View {
        let stats = snapshot?.usage?.summary
        let compactWidth = (Self.contentFrame.width - 69) / 4
        return HStack(spacing: 0) {
            metric("累计 Token 数", TokenFormat.count(stats?.lifetimeTokens), width: compactWidth)
            metric("Token 使用峰值", TokenFormat.count(stats?.peakDailyTokens), width: compactWidth, divided: true)
            metric("最长任务用时", TokenFormat.duration(stats?.longestRunningTurnSec), width: 69, divided: true)
            metric("最长连续天数", TokenFormat.days(stats?.longestStreakDays), width: compactWidth, divided: true)
            metric("当前连续天数", TokenFormat.days(stats?.currentStreakDays), width: compactWidth, divided: true)
        }
    }

    private func metric(_ label: String, _ value: String, width: CGFloat, divided: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 6.4, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

    private func todayLabel(_ activity: ActivityCalendar) -> String {
        guard activity.todayTokens != nil else { return "今日 TOKENS" }
        return activity.todayIsLocal ? "今日 TOKENS · 本机" : "今日 TOKENS · 账户"
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
