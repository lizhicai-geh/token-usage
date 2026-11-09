import SwiftUI

@main
struct CodexTokenApp: App {
    @NSApplicationDelegateAdaptor(UsageController.self) private var controller

    var body: some Scene {
        WindowGroup("Token Usage") {
            CodexTokenWindow(controller: controller)
        }
        .handlesExternalEvents(matching: [ActivityDayLink.route])
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

private struct CodexTokenWindow: View {
    @ObservedObject var controller: UsageController

    var body: some View {
        VStack(spacing: 14) {
            LCDPanel(snapshot: controller.snapshot, date: .now,
                     activityInteraction: .hover($controller.selectedActivityDay))
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

            Text("在桌面编辑小组件，选择 Token Usage 的大尺寸。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 386)
        .handlesExternalEvents(preferring: [ActivityDayLink.route], allowing: [ActivityDayLink.route])
        .onOpenURL { url in
            if let day = ActivityDayLink.date(from: url) {
                controller.selectedActivityDay = day
            }
        }
    }
}
