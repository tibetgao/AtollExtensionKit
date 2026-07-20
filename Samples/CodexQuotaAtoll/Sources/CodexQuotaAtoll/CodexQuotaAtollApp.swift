import CodexQuotaCore
import Darwin
import Foundation

@main
@MainActor
struct CodexQuotaAtollApp {
    static func main() async {
        let options = Options(arguments: CommandLine.arguments)
        let client = CodexAppServerClient()
        let presenter = AtollQuotaPresenter()

        do {
            guard presenter.isAtollInstalled else {
                throw AppError.atollNotInstalled
            }
            guard try await withTimeout(seconds: 15, operation: {
                try await presenter.requestAuthorization()
            }) else {
                throw AppError.authorizationDenied
            }

            repeat {
                do {
                    let result = try await withTimeout(seconds: 20) {
                        try await client.readRateLimits()
                    }
                    let snapshot = CodexQuotaSnapshot(result: result)
                    try await withTimeout(seconds: 15) {
                        try await presenter.show(snapshot)
                    }
                    printStatus(snapshot)
                } catch {
                    FileHandle.standardError.write(Data("Refresh failed: \(error.localizedDescription)\n".utf8))
                    if options.once { throw error }
                }

                if !options.once {
                    try await Task.sleep(for: .seconds(options.interval))
                }
            } while !options.once
        } catch {
            FileHandle.standardError.write(Data("codex-quota-atoll: \(error.localizedDescription)\n".utf8))
            await presenter.dismiss()
            await presenter.close()
            await client.stop()
            exit(EXIT_FAILURE)
        }

        await presenter.close()
        await client.stop()
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

    private static func printStatus(_ snapshot: CodexQuotaSnapshot) {
        let short = snapshot.shortWindow.map {
            "\(snapshot.label(for: $0)) \(Int($0.remainingPercent.rounded()))%"
        } ?? "primary n/a"
        let weekly = snapshot.weeklyWindow.map {
            "\(snapshot.label(for: $0)) \(Int($0.remainingPercent.rounded()))%"
        } ?? "secondary n/a"
        let credits = snapshot.credits?.balance.map { " credits \($0)" } ?? ""
        print("Codex quota: \(short), \(weekly)\(credits)")
    }
}

private struct Options {
    let once: Bool
    let interval: TimeInterval

    init(arguments: [String]) {
        once = arguments.contains("--once")
        if let index = arguments.firstIndex(of: "--interval"),
           arguments.indices.contains(index + 1),
           let value = TimeInterval(arguments[index + 1]), value >= 30 {
            interval = value
        } else {
            interval = 300
        }
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
