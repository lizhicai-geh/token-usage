import SwiftUI

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
