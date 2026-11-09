import AppKit
import Combine
import WidgetKit

@MainActor
final class UsageController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published var selectedActivityDay: Date?
    @Published private var localError: String?
    @Published private var accountError: String?
    @Published private var rateLimitsError: String?
    @Published private var isRefreshingLocal = false
    @Published private var isRefreshingAccount = false
    @Published private var isRefreshingRateLimits = false

    private let readAccount: @Sendable () async throws -> AccountUsage
    private let readRateLimits: @Sendable () async throws -> AccountRateLimits
    private let readLocal: @Sendable () async throws -> AccountUsage.DailyBucket?
    private let publish: (UsageSnapshot) throws -> Void
    private var refreshLoops: [Task<Void, Never>] = []

    var isRefreshing: Bool { isRefreshingLocal || isRefreshingAccount || isRefreshingRateLimits }
    var errorMessage: String? { localError ?? accountError ?? rateLimitsError }

    override convenience init() {
        self.init(
            snapshot: .load(),
            readAccount: {
                try await Task.detached(priority: .utility) {
                    try AppServerClient.installed().readUsage()
                }.value
            },
            readLocal: {
                try await Task.detached(priority: .utility) {
                    try LocalUsage.readToday()
                }.value
            },
            readRateLimits: {
                try await Task.detached(priority: .utility) {
                    try AppServerClient.installed().readRateLimits()
                }.value
            },
            publish: { snapshot in
                try snapshot.save()
                WidgetCenter.shared.reloadTimelines(ofKind: UsageSnapshot.widgetKind)
            }
        )
    }

    init(snapshot: UsageSnapshot?, readAccount: @escaping @Sendable () async throws -> AccountUsage,
         readLocal: @escaping @Sendable () async throws -> AccountUsage.DailyBucket?,
         readRateLimits: @escaping @Sendable () async throws -> AccountRateLimits,
         publish: @escaping (UsageSnapshot) throws -> Void) {
        self.snapshot = snapshot
        self.readAccount = readAccount
        self.readLocal = readLocal
        self.readRateLimits = readRateLimits
        self.publish = publish
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshLoops = [poll(refreshLocal), poll(refreshAccount), poll(refreshRateLimits)]
    }

    func applicationWillTerminate(_ notification: Notification) {
        for loop in refreshLoops { loop.cancel() }
    }

    func refresh() async {
        async let local: Void = refreshLocal()
        async let account: Void = refreshAccount()
        async let rateLimits: Void = refreshRateLimits()
        _ = await (local, account, rateLimits)
    }

    func refreshLocal() async {
        guard !isRefreshingLocal else { return }
        isRefreshingLocal = true
        defer { isRefreshingLocal = false }

        do {
            let local = try await readLocal()
            try updateSnapshot {
                $0.localToday = local
                $0.localFetchedAt = .now
            }
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }

    func refreshAccount() async {
        guard !isRefreshingAccount else { return }
        isRefreshingAccount = true
        defer { isRefreshingAccount = false }

        let usage: AccountUsage
        do {
            usage = try await readAccount()
        } catch {
            accountError = error.localizedDescription
            if snapshot?.accountUnavailable != true {
                try? updateSnapshot { $0.accountUnavailable = true }
            }
            return
        }

        do {
            try updateSnapshot {
                $0.usage = usage
                $0.fetchedAt = .now
                $0.accountUnavailable = false
            }
            accountError = nil
        } catch {
            accountError = error.localizedDescription
        }
    }

    func refreshRateLimits() async {
        guard !isRefreshingRateLimits else { return }
        isRefreshingRateLimits = true
        defer { isRefreshingRateLimits = false }

        let limits: AccountRateLimits
        do {
            limits = try await readRateLimits()
        } catch {
            rateLimitsError = "额度查询失败：\(error.localizedDescription)"
            if snapshot?.rateLimitsUnavailable != true {
                try? updateSnapshot { $0.rateLimitsUnavailable = true }
            }
            return
        }

        do {
            try updateSnapshot {
                $0.rateLimits = limits
                $0.rateLimitsFetchedAt = .now
                $0.rateLimitsUnavailable = false
            }
            rateLimitsError = nil
        } catch {
            rateLimitsError = "额度保存失败：\(error.localizedDescription)"
        }
    }

    private func updateSnapshot(_ update: (inout UsageSnapshot) -> Void) throws {
        var updated = snapshot ?? UsageSnapshot()
        update(&updated)
        try publish(updated)
        snapshot = updated
    }

    private func poll(_ refresh: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task {
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
}
