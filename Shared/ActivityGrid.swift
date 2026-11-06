import SwiftUI

struct ActivityGrid: View {
    enum Interaction {
        case none
        case hover(Binding<Date?>)
        case widgetLinks
    }

    let activity: ActivityCalendar
    let calendar: Calendar
    let ink: Color
    let interaction: Interaction

    private static let width: CGFloat = 273
    private static let height: CGFloat = 76
    private static let cellSide: CGFloat = 7.75
    private static let columnStep = width / CGFloat(ActivityCalendar.weekCount)

    private struct Cell: Identifiable {
        let day: ActivityCalendar.Day
        let frame: CGRect
        var id: Date { day.date }
    }

    var body: some View {
        let cells = activity.weeks.enumerated().flatMap { column, week in
            week.days.enumerated().compactMap { row, day -> Cell? in
                guard !day.isFuture else { return nil }
                return Cell(day: day, frame: CGRect(
                    x: CGFloat(column) * Self.columnStep, y: 16 + CGFloat(row) * 8.75,
                    width: Self.cellSide, height: Self.cellSide
                ))
            }
        }
        switch interaction {
        case .hover(let selection):
            let selected = cells.first { $0.id == selection.wrappedValue }
            let selectAt: (CGPoint) -> Void = { location in
                let day = cells.first { $0.frame.contains(location) }?.id
                if selection.wrappedValue != day { selection.wrappedValue = day }
            }
            grid(cells, selected: selected?.id)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        selectAt(location)
                    case .ended:
                        if selection.wrappedValue != nil { selection.wrappedValue = nil }
                    }
                }
                .onTapGesture { location in selectAt(location) }
                .overlay(alignment: .topLeading) {
                    if let selected { tooltip(for: selected) }
                }
        case .none, .widgetLinks:
            grid(cells, selected: nil)
        }
    }

    private func grid(_ cells: [Cell], selected: Date?) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for (column, week) in activity.weeks.enumerated() {
                    guard let month = week.month else { continue }
                    let label = Text("\(month)月").font(.system(size: 7, weight: .medium)).foregroundStyle(ink)
                    let x = CGFloat(column) * Self.columnStep + 2
                    context.draw(label, at: CGPoint(x: x, y: 7), anchor: .leading)
                }
            }
            .accessibilityHidden(true)

            ForEach(cells) { cell in
                cellView(cell, isSelected: selected == cell.id)
                    .position(x: cell.frame.midX, y: cell.frame.midY)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("最近 \(ActivityCalendar.weekCount) 周 Token 活动")
    }

    @ViewBuilder
    private func cellView(_ cell: Cell, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1.8)
        let square = shape
            .fill(ink.opacity(opacity(cell.day.tokens)))
            .overlay {
                if isSelected { shape.strokeBorder(.white.opacity(0.85), lineWidth: 0.8) }
            }
            .frame(width: Self.cellSide, height: Self.cellSide)
        if case .widgetLinks = interaction, let destination = ActivityDayLink.url(for: cell.day.date) {
            Link(destination: destination) { square.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(dateLabel(cell.day))
                .accessibilityValue(tokenLabel(cell.day))
        } else {
            square
                .accessibilityElement()
                .accessibilityLabel(dateLabel(cell.day))
                .accessibilityValue(tokenLabel(cell.day))
        }
    }

    private func tooltip(for cell: Cell) -> some View {
        let width: CGFloat = 114
        let height: CGFloat = 44
        let left = min(max(0, cell.frame.midX), Self.width - width)
        let bubble = RoundedRectangle(cornerRadius: 15)
        return VStack(alignment: .leading, spacing: 2) {
            Text(dateLabel(cell.day))
            Text(tokenLabel(cell.day))
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: width - 24, alignment: .leading)
        .frame(width: width, height: height)
        .background(Color(white: 0.17), in: bubble)
        .overlay { bubble.strokeBorder(Color(white: 0.23), lineWidth: 1) }
        .position(x: left + width / 2, y: cell.frame.minY - 4 - height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dateLabel(_ day: ActivityCalendar.Day) -> String {
        "\(calendar.component(.month, from: day.date))月\(calendar.component(.day, from: day.date))日"
    }

    private func tokenLabel(_ day: ActivityCalendar.Day) -> String {
        day.tokens.map { "\(TokenFormat.count($0)) 个 Token" } ?? "暂无用量数据"
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
