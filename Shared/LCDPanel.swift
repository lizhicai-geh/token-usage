import SwiftUI

struct LCDPanel: View {
    enum Layout {
        case app, small, medium, large
    }

    let snapshot: UsageSnapshot?
    let date: Date
    var layout: Layout = .app
    var activityInteraction: ActivityGrid.Interaction = .none
    @State private var isHoveringAllowance = false

    private static let side: CGFloat = 346
    private static let ink = Color(red: 0.065, green: 0.080, blue: 0.069)
    private static let divider = ink.opacity(0.28)
    private static let screenSize = CGSize(width: 290, height: 290)
    private static let contentFrame = CGRect(x: 28, y: 28, width: screenSize.width, height: screenSize.height)
        .insetBy(dx: 12, dy: 12)
    private static let mediumWeekCount = 17

    private var compactBezel: Bool { layout == .large }
    private var panelSize: CGSize {
        switch layout {
        case .small: CGSize(width: 158, height: 158)
        case .medium: CGSize(width: 344, height: 158)
        case .app, .large: CGSize(width: Self.side, height: Self.side)
        }
    }

    private var includesActivityHistory: Bool {
        if case .hover = activityInteraction { return true }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            let size = panelSize
            let scale = min(geometry.size.width / size.width, geometry.size.height / size.height)
            face
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .environment(\.colorScheme, .light)
    }

    private var face: some View {
        let calendar = Calendar.localGregorian
        let activity = ActivityCalendar(
            usage: snapshot?.usage, localToday: snapshot?.localToday, preferLocalToday: snapshot?.accountUnavailable == true,
            date: date, calendar: calendar, includeHistory: includesActivityHistory,
            weekCount: layout == .medium ? Self.mediumWeekCount : ActivityCalendar.weekCount
        )
        let readout = TokenFormat.lcd(activity.todayTokens)

        return Group {
            if layout == .small || layout == .medium {
                compactFace(activity: activity, calendar: calendar, readout: readout)
            } else {
                ZStack(alignment: .topLeading) {
                    bezel
                    screenContent(activity: activity, calendar: calendar, readout: readout)
                        .frame(width: Self.side, height: Self.side)
                        // Leave a 12-point bezel in widgets; retain the app's 28-point bezel.
                        .scaleEffect(compactBezel ? (Self.side - 24) / Self.screenSize.width : 1)
                }
            }
        }
        .foregroundStyle(Self.ink)
    }

    private func compactFace(activity: ActivityCalendar, calendar: Calendar,
                             readout: TokenFormat.Readout) -> some View {
        let dateStyle = UsageLocale.dateStyle(calendar: calendar)
        return ZStack {
            outerBezel(cornerRadius: 24).padding(3)
            innerBezel(cornerRadius: 15).padding(6)
            screenSurface.padding(9)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(date.formatted(dateStyle.month(.twoDigits).day(.twoDigits))).monospacedDigit()
                        Text(date.formatted(dateStyle.weekday(.wide)))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)

                    tokenReadout(readout, activity: activity).frame(height: 40)
                    Text(todayLabel(activity))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityHidden(true)

                    Rectangle().fill(Self.divider).frame(height: 0.65)
                        .accessibilityHidden(true)
                    compactAllowance
                }
                .frame(width: 122)

                if layout == .medium {
                    Rectangle().fill(Self.divider).frame(width: 0.65, height: 104)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近 \(Self.mediumWeekCount) 周活动")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        ActivityGrid(activity: activity, calendar: calendar, ink: Self.ink, interaction: activityInteraction)
                    }
                }
            }
        }
    }

    private var compactAllowance: some View {
        let limits = snapshot?.rateLimits
        let unavailable = snapshot?.rateLimitsUnavailable == true
        return HStack(spacing: 2) {
            allowanceRing.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(limits?.label ?? String(localized: "额度"))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                Text(unavailable ? String(localized: "暂不可用") : (limits?.value ?? "—"))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前额度")
        .accessibilityValue(allowanceDescription)
    }

    private func screenContent(activity: ActivityCalendar, calendar: Calendar, readout: TokenFormat.Readout) -> some View {
        let dateStyle = UsageLocale.dateStyle(calendar: calendar)
        return ZStack(alignment: .topLeading) {
            screen
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(dateStyle.month(.twoDigits).day(.twoDigits)))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(date.formatted(dateStyle.weekday(.wide)))
                    .font(.system(size: 8, weight: .medium))
            }
            .offset(x: Self.contentFrame.minX, y: Self.contentFrame.minY)

            allowance
                .frame(width: 34, height: 34)
                .position(x: Self.contentFrame.maxX - 11.5, y: Self.contentFrame.minY + 11.5)
                .zIndex(1)

            tokenReadout(readout, activity: activity)
                .frame(width: 246, height: 60)
                .position(x: 170, y: 113)

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
            .accessibilityLabel("当前额度")
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
        if unavailable { return String(localized: "额度暂时无法读取") }
        guard let limits else { return String(localized: "额度暂无数据") }
        let value = limits.value
        let title = limits.label
        return stale ? String(localized: "\(title) · \(value) · 缓存数据") : "\(title) · \(value)"
    }

    private var allowanceTooltip: some View {
        let limits = snapshot?.rateLimits
        let title = limits?.label ?? String(localized: "额度")
        let unavailable = snapshot?.rateLimitsUnavailable == true
        let stale = snapshot?.rateLimitsFetchedAt.map { date.timeIntervalSince($0) > 3 * UsageSnapshot.refreshInterval } ?? false
        let value = unavailable ? String(localized: "暂不可用") : (limits?.value ?? String(localized: "暂无数据"))
        let detail = stale && !unavailable ? String(localized: "\(value)（缓存）") : value
        let bubble = RoundedRectangle(cornerRadius: 12)

        return HStack(spacing: 0) {
            Text(title).fontWeight(.semibold)
            Text(" · " + detail).fontWeight(.regular)
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
            outerBezel(cornerRadius: 35)
                .frame(width: compactBezel ? 338 : 328, height: compactBezel ? 338 : 328)
                .position(x: 173, y: 173)

            innerBezel(cornerRadius: 18)
                .frame(width: compactBezel ? 330 : 303, height: compactBezel ? 330 : 303)
                .position(x: 173, y: 173)
        }
        .accessibilityHidden(true)
    }

    private func outerBezel(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return shape
            .fill(.linearGradient(colors: [Color(white: 0.93), Color(white: 0.982), Color(white: 0.91)],
                                  startPoint: .top, endPoint: .bottom))
            .overlay { shape.strokeBorder(.white.opacity(0.75), lineWidth: 1) }
            .accessibilityHidden(true)
    }

    private func innerBezel(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.linearGradient(colors: [Color(white: 0.76), .white], startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }

    private var screen: some View {
        screenSurface
            .frame(width: Self.screenSize.width, height: Self.screenSize.height)
            .position(x: 173, y: 173)
    }

    private var screenSurface: some View {
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

    private func metric(_ label: LocalizedStringKey, _ value: String, width: CGFloat, divided: Bool = false) -> some View {
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
        guard activity.todayTokens != nil else { return String(localized: "今日 TOKENS") }
        return activity.todayIsLocal ? String(localized: "今日 TOKENS · 本机") : String(localized: "今日 TOKENS · 账户")
    }

    private func tokenReadout(_ readout: TokenFormat.Readout, activity: ActivityCalendar) -> some View {
        SegmentReadout(readout: readout)
            .accessibilityLabel(todayLabel(activity))
            .accessibilityValue(activity.todayTokens?.formatted(.number.locale(UsageLocale.current)) ?? String(localized: "暂无数据"))
    }

    private struct SegmentReadout: View {
        let readout: TokenFormat.Readout

        var body: some View {
            let glyphs = (readout.digits + readout.unit).compactMap { LCDGlyphs.glyphs[$0] }
            let spacing = LCDGlyphs.spacing
            let height = LCDGlyphs.height

            return Canvas { context, size in
                guard !glyphs.isEmpty else { return }
                let width = glyphs.reduce(CGFloat(0)) { $0 + $1.width } + CGFloat(glyphs.count - 1) * spacing
                let scale = min(size.width / width, size.height / height)
                guard scale > 0 else { return }
                var context = context
                context.translateBy(x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                for glyph in glyphs {
                    context.fill(glyph.unlit, with: .color(ink.opacity(0.115)))
                    context.fill(glyph.lit, with: .color(ink))
                    context.translateBy(x: glyph.width + spacing, y: 0)
                }
            }
        }
    }
}
