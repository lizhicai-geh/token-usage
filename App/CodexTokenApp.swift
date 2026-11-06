import AppKit
import SwiftUI
import WidgetKit

@main
struct CodexTokenApp: App {
    @NSApplicationDelegateAdaptor(UsageController.self) private var controller

    var body: some Scene {
        WindowGroup("Codex Token") {
            VStack(spacing: 14) {
                LCDPanel(snapshot: controller.snapshot, date: .now)
                    .frame(width: 346, height: 346)

                if let error = controller.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button("立即刷新") {
                        Task { await controller.refresh() }
                    }
                    .disabled(controller.isRefreshing)
                    if controller.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }

                Text("在桌面编辑小组件，选择 Codex Token 的大尺寸。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(minWidth: 386)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class UsageController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.load()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    private var refreshLoop: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshLoop = Task {
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let nextRefresh = clock.now + .seconds(60)
                await refresh()
                do {
                    try await clock.sleep(until: nextRefresh)
                } catch {
                    break
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshLoop?.cancel()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let updated = try await Task.detached(priority: .utility) {
                let client = try AppServerClient.installed()
                let usage = try client.readUsage()
                let now = Date.now
                let calendar = Calendar.localGregorian
                let today = calendar.usageDateKey(for: now)
                let hasAccountToday = usage.dailyUsageBuckets?.contains { $0.startDate == today } == true
                let localToday = hasAccountToday ? nil : LocalUsage.readToday(codexHome: LocalUsage.codexHome, date: now, calendar: calendar)
                return UsageSnapshot(usage: usage, fetchedAt: now, localToday: localToday)
            }.value
            try updated.save()
            snapshot = updated
            errorMessage = nil
            WidgetCenter.shared.reloadTimelines(ofKind: UsageSnapshot.widgetKind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
