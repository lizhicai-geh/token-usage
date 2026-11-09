import SwiftUI
import WidgetKit

@main
struct CodexTokenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: UsageSnapshot.widgetKind, provider: UsageProvider()) { entry in
            LCDPanel(
                snapshot: entry.snapshot, date: entry.date, isPreview: entry.isPreview, compactBezel: true,
                activityInteraction: entry.isPreview ? .none : .widgetLinks
            )
                .containerBackground(for: .widget) { Color(white: 0.96) }
        }
        .configurationDisplayName("Token Usage")
        .description("以液晶仪表查看今日 Token、每日活动和账户统计。")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

private struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var isPreview = false
}

private struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        let date = Date()
        return UsageEntry(date: date, snapshot: .preview(at: date), isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let date = Date()
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(UsageEntry(date: date, snapshot: .load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let snapshot = UsageSnapshot.load()
        let entries = [UsageEntry(date: now, snapshot: snapshot)]
        let midnight = Calendar.localGregorian.dateInterval(of: .day, for: now)?.end ?? .distantFuture
        let next = min(midnight, now.addingTimeInterval(UsageSnapshot.refreshInterval))
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}
