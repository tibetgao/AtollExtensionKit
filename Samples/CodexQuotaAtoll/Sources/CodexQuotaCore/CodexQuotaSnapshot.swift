import Foundation

public struct CodexRateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int
    public let resetsAt: Int64

    public var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    public var resetDate: Date {
        Date(timeIntervalSince1970: TimeInterval(resetsAt))
    }
}

public struct CodexCredits: Codable, Equatable, Sendable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: String?
}

public struct CodexRateLimits: Codable, Equatable, Sendable {
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let credits: CodexCredits?
    public let planType: String?
    public let rateLimitReachedType: String?
    public let spendControlReached: Bool?
}

public struct CodexRateLimitsResult: Codable, Equatable, Sendable {
    public let rateLimits: CodexRateLimits
}

public struct CodexQuotaSnapshot: Equatable, Sendable {
    public let shortWindow: CodexRateLimitWindow?
    public let weeklyWindow: CodexRateLimitWindow?
    public let credits: CodexCredits?
    public let planType: String?
    public let limitReached: Bool

    public init(result: CodexRateLimitsResult) {
        shortWindow = result.rateLimits.primary
        weeklyWindow = result.rateLimits.secondary
        credits = result.rateLimits.credits
        planType = result.rateLimits.planType
        limitReached = result.rateLimits.rateLimitReachedType != nil
            || result.rateLimits.spendControlReached == true
    }

    public var headlineWindow: CodexRateLimitWindow? {
        shortWindow ?? weeklyWindow
    }

    public func label(for window: CodexRateLimitWindow) -> String {
        switch window.windowDurationMins {
        case 300: return "5h"
        case 10_080: return "Week"
        default:
            if window.windowDurationMins.isMultiple(of: 1_440) {
                return "\(window.windowDurationMins / 1_440)d"
            }
            if window.windowDurationMins.isMultiple(of: 60) {
                return "\(window.windowDurationMins / 60)h"
            }
            return "\(window.windowDurationMins)m"
        }
    }

    public var lowestRemainingPercent: Double? {
        [shortWindow, weeklyWindow]
            .compactMap { $0?.remainingPercent }
            .min()
    }
}

public struct CodexThreadListResult: Codable, Equatable, Sendable {
    public let data: [CodexThreadSummary]
}

public struct CodexThreadSummary: Codable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let preview: String
    public let cwd: String
    public let status: CodexThreadStatus
    public let modelProvider: String
    public let createdAt: Int64
    public let updatedAt: Int64

    public var displayName: String {
        let candidate = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty { return candidate }
        let preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "Untitled task" : preview
    }
}

public enum CodexThreadStatus: Equatable, Sendable, Codable {
    case notLoaded
    case idle
    case active(waitingOnApproval: Bool, waitingOnUserInput: Bool)
    case systemError
    case unknown(String)

    private enum CodingKeys: String, CodingKey { case type, activeFlags }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let flags = try container.decodeIfPresent([String].self, forKey: .activeFlags) ?? []
        switch type {
        case "notLoaded": self = .notLoaded
        case "idle": self = .idle
        case "active":
            self = .active(
                waitingOnApproval: flags.contains("waitingOnApproval"),
                waitingOnUserInput: flags.contains("waitingOnUserInput")
            )
        case "systemError": self = .systemError
        default: self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notLoaded: try container.encode("notLoaded", forKey: .type)
        case .idle: try container.encode("idle", forKey: .type)
        case .systemError: try container.encode("systemError", forKey: .type)
        case .unknown(let type): try container.encode(type, forKey: .type)
        case .active(let approval, let input):
            try container.encode("active", forKey: .type)
            var flags: [String] = []
            if approval { flags.append("waitingOnApproval") }
            if input { flags.append("waitingOnUserInput") }
            try container.encode(flags, forKey: .activeFlags)
        }
    }
}

public enum CodexTaskActivity: String, Equatable, Sendable {
    case running
    case waiting
    case idle
    case failed
}

public struct CodexDashboardSnapshot: Equatable, Sendable {
    public let quota: CodexQuotaSnapshot
    public let threads: [CodexThreadSummary]
    public let activity: CodexTaskActivity
    public let refreshedAt: Date

    public init(
        quota: CodexQuotaSnapshot,
        threads: [CodexThreadSummary],
        activity: CodexTaskActivity,
        refreshedAt: Date = Date()
    ) {
        self.quota = quota
        self.threads = threads
        self.activity = activity
        self.refreshedAt = refreshedAt
    }

    public var latestThread: CodexThreadSummary? { threads.first }
}

public enum LocalCodexActivityMonitor {
    public static func activity(
        for thread: CodexThreadSummary?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CodexTaskActivity {
        guard let thread else { return .idle }
        switch thread.status {
        case .active(let approval, let input):
            return approval || input ? .waiting : .running
        case .systemError:
            return .failed
        case .idle:
            return .idle
        case .notLoaded, .unknown:
            break
        }

        let sessions = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return .idle }

        for case let url as URL in enumerator where
            url.pathExtension == "jsonl" && url.lastPathComponent.contains(thread.id)
        {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return .idle }
            var lastLifecycleEvent: String?
            for line in text.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      object["type"] as? String == "event_msg",
                      let payload = object["payload"] as? [String: Any],
                      let type = payload["type"] as? String,
                      type == "task_started" || type == "task_complete" else { continue }
                lastLifecycleEvent = type
            }
            return lastLifecycleEvent == "task_started" ? .running : .idle
        }
        return .idle
    }
}
