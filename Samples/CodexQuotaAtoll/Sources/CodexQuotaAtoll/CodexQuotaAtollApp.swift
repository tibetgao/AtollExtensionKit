import CodexQuotaCore
import Darwin
import Foundation

@main
@MainActor
struct CodexQuotaAtollApp {
    static func main() async {
        let options = Options(arguments: CommandLine.arguments)
        let client = CodexAppServerClient()
        let preferences = CodexDashboardPreferences()
        let presenter = AtollQuotaPresenter(preferences: preferences)
        let cache = CodexDashboardCache()
        let interactionServer = CodexInteractionServer(preferences: preferences)
        var currentSnapshot: CodexDashboardSnapshot?

        do {
            guard presenter.isAtollInstalled else {
                throw AppError.atollNotInstalled
            }
            guard try await withTimeout(seconds: 15, operation: {
                try await presenter.requestAuthorization()
            }) else {
                throw AppError.authorizationDenied
            }
            await presenter.removeLegacyActivity()
            try interactionServer.start()

            if let cached = cache.load() {
                currentSnapshot = cached
                interactionServer.update(snapshot: cached)
                try await withTimeout(seconds: 8) {
                    try await presenter.show(cached)
                }
                print("Codex dashboard: restored cached snapshot")
            }

            var nextFullRefresh = Date.distantPast
            repeat {
                let now = Date()
                if now >= nextFullRefresh {
                    nextFullRefresh = now.addingTimeInterval(options.interval)
                    do {
                        // Quota is intentionally fetched separately from the
                        // deeper session history. A slow historical page must
                        // never prevent the compact quota strip from updating.
                        let limits = try await withTimeout(seconds: 15) {
                            try await client.readRateLimits()
                        }
                        let threads: [CodexThreadSummary]
                        do {
                            threads = try await withTimeout(seconds: 40) {
                                try await client.listThreadHistory(maximumCount: 100)
                            }
                        } catch {
                            guard let cachedThreads = currentSnapshot?.threads,
                                  !cachedThreads.isEmpty else { throw error }
                            threads = cachedThreads
                            FileHandle.standardError.write(Data("Session history refresh failed; retaining \(cachedThreads.count) cached sessions: \(error.localizedDescription)\n".utf8))
                        }
                        let observations = await Task.detached {
                            LocalCodexActivityMonitor.observations(for: threads)
                        }.value
                        let dashboard = CodexDashboardSnapshot(
                            quota: CodexQuotaSnapshot(result: limits),
                            threads: threads,
                            activities: observations.mapValues(\.activity),
                            details: observations.mapValues(\.details)
                        )
                        currentSnapshot = dashboard
                        interactionServer.update(snapshot: dashboard)
                        try? cache.save(dashboard)
                        try await withTimeout(seconds: 15) {
                            try await presenter.show(dashboard)
                        }
                        printStatus(dashboard)
                    } catch {
                        FileHandle.standardError.write(Data("Refresh failed: \(error.localizedDescription)\n".utf8))
                        if let snapshot = currentSnapshot {
                            let degraded = degradedSnapshot(snapshot, for: error)
                            currentSnapshot = degraded
                            interactionServer.update(snapshot: degraded)
                            try? cache.save(degraded)
                            try? await presenter.show(degraded)
                        } else if options.once {
                            throw error
                        }
                    }
                }

                guard !options.once else { break }

                if let snapshot = currentSnapshot {
                    let liveThreads = snapshot.threads.filter {
                        switch snapshot.activity(for: $0) {
                        case .preparing, .running, .waitingForApproval, .waitingForInput, .reconnecting:
                            return true
                        default:
                            return false
                        }
                    }
                    let recentThreads = Array((liveThreads.isEmpty ? Array(snapshot.threads.prefix(1)) : liveThreads).prefix(5))
                    let recentObservations = await Task.detached {
                        LocalCodexActivityMonitor.observations(for: recentThreads)
                    }.value
                    var activities = snapshot.activities
                    activities.merge(recentObservations.mapValues(\.activity)) { _, latest in latest }
                    var details = snapshot.details ?? [:]
                    details.merge(recentObservations.mapValues(\.details)) { _, latest in latest }
                    if activities != snapshot.activities || details != snapshot.details {
                        let updated = snapshot.updatingMonitoring(activities: activities, details: details)
                        currentSnapshot = updated
                        interactionServer.update(snapshot: updated)
                        try? cache.save(updated)
                        try? await presenter.show(updated)
                        printStatus(updated)
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(options.activityPollInterval))
                } catch is CancellationError {
                    break
                }
            } while true
        } catch {
            FileHandle.standardError.write(Data("codex-quota-atoll: \(error.localizedDescription)\n".utf8))
            await presenter.close()
            await client.stop()
            interactionServer.stop()
            exit(EXIT_FAILURE)
        }

        await presenter.close()
        await client.stop()
        interactionServer.stop()
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate(continuation)
            Task {
                do {
                    await gate.resume(with: .success(try await operation()))
                } catch {
                    await gate.resume(with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                await gate.resume(with: .failure(AppError.timeout(seconds)))
            }
        }
    }

    private static func printStatus(_ dashboard: CodexDashboardSnapshot) {
        let snapshot = dashboard.quota
        let short = snapshot.shortWindow.map {
            "\(snapshot.label(for: $0)) \(Int($0.remainingPercent.rounded()))%"
        } ?? "primary n/a"
        let weekly = snapshot.weeklyWindow.map {
            "\(snapshot.label(for: $0)) \(Int($0.remainingPercent.rounded()))%"
        } ?? "secondary n/a"
        let credits = snapshot.credits?.balance.map { " credits \($0)" } ?? ""
        print("Codex dashboard: \(short), \(weekly)\(credits), \(dashboard.activity.rawValue)")
    }

    private static func degradedSnapshot(
        _ snapshot: CodexDashboardSnapshot,
        for error: Error
    ) -> CodexDashboardSnapshot {
        guard let latest = snapshot.latestThread,
              snapshot.activity.needsUserAction == false else { return snapshot }
        var activities = snapshot.activities
        if case AppError.timeout = error {
            activities[latest.id] = .timedOut
        } else {
            activities[latest.id] = .disconnected
        }
        return snapshot.updatingActivities(activities)
    }
}

private struct Options {
    let once: Bool
    let interval: TimeInterval
    let activityPollInterval: TimeInterval

    init(arguments: [String]) {
        once = arguments.contains("--once")
        if let index = arguments.firstIndex(of: "--interval"),
           arguments.indices.contains(index + 1),
           let value = TimeInterval(arguments[index + 1]), value >= 30 {
            interval = value
        } else {
            interval = 300
        }
        activityPollInterval = 2
    }
}

private enum AppError: LocalizedError {
    case atollNotInstalled
    case authorizationDenied
    case timeout(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .atollNotInstalled:
            return "Atoll is not installed. Install and launch Atoll before running this companion."
        case .authorizationDenied:
            return "Atoll authorization was denied. Enable this app in Atoll Settings → Extensions."
        case .timeout(let seconds):
            return "The operation timed out after \(Int(seconds)) seconds. Ensure Atoll and Codex are running."
        }
    }
}

private actor ContinuationGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
