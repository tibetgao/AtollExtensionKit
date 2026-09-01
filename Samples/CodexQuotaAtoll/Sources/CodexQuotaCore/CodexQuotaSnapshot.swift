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

public struct CodexQuotaSnapshot: Codable, Equatable, Sendable {
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
    public let nextCursor: String?
    public let backwardsCursor: String?
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

public enum CodexTaskActivity: String, Codable, Equatable, Sendable {
    case preparing
    case running
    case waitingForApproval
    case waitingForInput
    case reconnecting
    case completed
    case idle
    case cancelled
    case timedOut
    case failed
    case disconnected

    public var needsUserAction: Bool {
        self == .waitingForApproval || self == .waitingForInput
    }
}

public struct CodexPlanStep: Codable, Equatable, Sendable {
    public let text: String
    public let status: String

    public init(text: String, status: String) {
        self.text = text
        self.status = status
    }
}

public struct CodexQuestionOption: Codable, Equatable, Sendable {
    public let label: String
    public let detail: String?

    public init(label: String, detail: String? = nil) {
        self.label = label
        self.detail = detail
    }
}

public struct CodexQuestionPrompt: Codable, Equatable, Sendable {
    public let title: String
    public let question: String
    public let options: [CodexQuestionOption]

    public init(title: String, question: String, options: [CodexQuestionOption]) {
        self.title = title
        self.question = question
        self.options = options
    }
}

public struct CodexSessionDetails: Codable, Equatable, Sendable {
    public let model: String?
    public let reasoningEffort: String?
    public let outputTokensPerSecond: Double?
    public let latestThinking: String?
    public let latestMessage: String?
    public let plan: [CodexPlanStep]
    public let question: CodexQuestionPrompt?
    public let turnStartedAt: Date?
    public let turnCompletedAt: Date?
    public let durationMilliseconds: Int64?

    public init(
        model: String? = nil,
        reasoningEffort: String? = nil,
        outputTokensPerSecond: Double? = nil,
        latestThinking: String? = nil,
        latestMessage: String? = nil,
        plan: [CodexPlanStep] = [],
        question: CodexQuestionPrompt? = nil,
        turnStartedAt: Date? = nil,
        turnCompletedAt: Date? = nil,
        durationMilliseconds: Int64? = nil
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.outputTokensPerSecond = outputTokensPerSecond
        self.latestThinking = latestThinking
        self.latestMessage = latestMessage
        self.plan = plan
        self.question = question
        self.turnStartedAt = turnStartedAt
        self.turnCompletedAt = turnCompletedAt
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct CodexDashboardSnapshot: Codable, Equatable, Sendable {
    public let quota: CodexQuotaSnapshot
    public let threads: [CodexThreadSummary]
    public let activities: [String: CodexTaskActivity]
    /// Optional keeps disk caches created by older companion builds readable.
    public let details: [String: CodexSessionDetails]?
    public let refreshedAt: Date

    public init(
        quota: CodexQuotaSnapshot,
        threads: [CodexThreadSummary],
        activities: [String: CodexTaskActivity],
        details: [String: CodexSessionDetails]? = nil,
        refreshedAt: Date = Date()
    ) {
        self.quota = quota
        self.threads = threads
        self.activities = activities
        self.details = details
        self.refreshedAt = refreshedAt
    }

    public var latestThread: CodexThreadSummary? { threads.first }
    public var activity: CodexTaskActivity {
        latestThread.flatMap { activities[$0.id] } ?? .idle
    }

    public func activity(for thread: CodexThreadSummary, at now: Date = Date()) -> CodexTaskActivity {
        let activity = activities[thread.id] ?? .idle
        if case .active = thread.status { return activity }

        // A detached app-server reports desktop tasks as `notLoaded`, so the
        // rollout is the primary activity source. Incomplete rollouts can end
        // without a terminal event after a crash, forced quit, or lost remote
        // connection. Age those orphaned states out instead of showing them as
        // active forever, while giving genuinely long-running work ample time.
        let age = max(0, now.timeIntervalSince1970 - TimeInterval(thread.updatedAt))
        switch activity {
        case .preparing where age > 30 * 60,
             .reconnecting where age > 30 * 60:
            return .timedOut
        case .running where age > 6 * 60 * 60:
            return .disconnected
        case .waitingForApproval where age > 24 * 60 * 60,
             .waitingForInput where age > 24 * 60 * 60:
            return .disconnected
        default:
            return activity
        }
    }

    public func details(for thread: CodexThreadSummary) -> CodexSessionDetails? {
        details?[thread.id]
    }

    public func isActiveSession(_ thread: CodexThreadSummary, at now: Date = Date()) -> Bool {
        switch activity(for: thread, at: now) {
        case .preparing, .running, .waitingForApproval, .waitingForInput, .reconnecting:
            return true
        default:
            return false
        }
    }

    public func isRecentCompletion(
        _ thread: CodexThreadSummary,
        within interval: TimeInterval = 120,
        at now: Date = Date()
    ) -> Bool {
        guard activity(for: thread, at: now) == .completed,
              let completedAt = details(for: thread)?.turnCompletedAt else {
            return false
        }
        let age = now.timeIntervalSince(completedAt)
        return age >= 0 && age < interval
    }

    public func updatingActivities(_ values: [String: CodexTaskActivity]) -> Self {
        .init(quota: quota, threads: threads, activities: values, details: details, refreshedAt: refreshedAt)
    }

    public func updatingMonitoring(
        activities: [String: CodexTaskActivity],
        details: [String: CodexSessionDetails]
    ) -> Self {
        .init(quota: quota, threads: threads, activities: activities, details: details, refreshedAt: refreshedAt)
    }
}

public enum LocalCodexActivityMonitor {
    public struct Observation: Equatable, Sendable {
        public let activity: CodexTaskActivity
        public let details: CodexSessionDetails
    }

    public static func observations(
        for threads: [CodexThreadSummary],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: Observation] {
        let rollouts = rolloutURLs(for: threads, homeDirectory: homeDirectory)
        return Dictionary(uniqueKeysWithValues: threads.map { thread in
            (thread.id, observation(for: thread, rolloutURL: rollouts[thread.id]))
        })
    }

    public static func activities(
        for threads: [CodexThreadSummary],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: CodexTaskActivity] {
        observations(for: threads, homeDirectory: homeDirectory).mapValues(\.activity)
    }

    public static func activity(
        for thread: CodexThreadSummary?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CodexTaskActivity {
        guard let thread else { return .idle }
        switch thread.status {
        case .active(let approval, let input):
            if approval { return .waitingForApproval }
            if input { return .waitingForInput }
            return .running
        case .systemError:
            return .failed
        case .idle:
            return .idle
        case .notLoaded, .unknown:
            break
        }

        let values = activities(for: [thread], homeDirectory: homeDirectory)
        return values[thread.id] ?? .idle
    }

    private static func observation(
        for thread: CodexThreadSummary,
        rolloutURL: URL?
    ) -> Observation {
        var state: CodexTaskActivity = .idle
        switch thread.status {
        case .active(let approval, let input):
            if approval { state = .waitingForApproval }
            else if input { state = .waitingForInput }
            else { state = .running }
        case .systemError: state = .failed
        default: break
        }

        guard let rolloutURL,
              let handle = try? FileHandle(forReadingFrom: rolloutURL) else {
            return Observation(activity: state, details: CodexSessionDetails())
        }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        // Recent activity changes are always near the tail. A bounded read keeps
        // a very long-running Codex task from causing periodic UI stalls.
        try? handle.seek(toOffset: end > 3_000_000 ? end - 3_000_000 : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else {
            return Observation(activity: state, details: CodexSessionDetails())
        }

        var model: String?
        var effort: String?
        var latestThinking: String?
        var latestMessage: String?
        var plan: [CodexPlanStep] = []
        var question: CodexQuestionPrompt?
        var turnStartedAt: Date?
        var turnCompletedAt: Date?
        var durationMilliseconds: Int64?
        var outputAtStart: Int64?
        var latestOutput: Int64?
        var previousTokenDate: Date?
        var previousTokenOutput: Int64?
        var latestTokenRate: Double?
        var latestEventDate: Date?
        let iso = ISO8601DateFormatter()
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsedDate: (Any?) -> Date? = { value in
            if let value = value as? String {
                return fractionalISO.date(from: value) ?? iso.date(from: value)
            }
            if let value = numericDouble(value) {
                return Date(timeIntervalSince1970: value)
            }
            return nil
        }

        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let topType = object["type"] as? String else { continue }
            let eventDate = parsedDate(object["timestamp"])
            if let eventDate { latestEventDate = eventDate }

            if topType == "turn_context", let payload = object["payload"] as? [String: Any] {
                model = payload["model"] as? String ?? model
                effort = payload["effort"] as? String ?? payload["reasoning_effort"] as? String ?? effort
                continue
            }

            if topType == "response_item", let payload = object["payload"] as? [String: Any] {
                let type = payload["type"] as? String
                if type == "custom_tool_call" || type == "function_call" {
                    let name = payload["name"] as? String ?? ""
                    let input = payload["input"] as? String
                        ?? payload["arguments"] as? String
                        ?? ""
                    if name == "update_plan" || input.contains("tools.update_plan(") {
                        let updatedPlan = planSteps(fromToolInput: input)
                        if !updatedPlan.isEmpty { plan = updatedPlan }
                        state = .running
                    } else if name == "request_user_input" || input.contains("tools.request_user_input(") {
                        state = .waitingForInput
                        question = questionPrompt(fromToolInput: input) ?? question
                    } else if input.contains("tools.request_permissions(")
                        || input.contains("tools.request_plugin_install(") {
                        state = .waitingForApproval
                    }
                }
                continue
            }

            guard topType == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            switch type {
            case "task_started":
                state = .preparing
                turnStartedAt = parsedDate(payload["started_at"]) ?? eventDate
                turnCompletedAt = nil
                durationMilliseconds = nil
                outputAtStart = latestOutput
                latestThinking = nil
                latestMessage = nil
                plan = []
                question = nil
            case "agent_reasoning":
                state = .running
                latestThinking = cleaned(payload["text"] as? String)
            case "agent_message":
                state = .running
                latestMessage = cleaned(payload["message"] as? String ?? payload["text"] as? String)
            case "exec_command_begin", "mcp_tool_call_begin", "web_search_begin", "patch_apply_begin": state = .running
            case "exec_approval_request", "apply_patch_approval_request", "dynamic_tool_call_request": state = .waitingForApproval
            case "request_user_input", "elicitation_request":
                state = .waitingForInput
                question = questionPrompt(from: payload)
            case "stream_error": state = .reconnecting
            case "error": state = .failed
            case "turn_aborted": state = .cancelled
            case "task_complete":
                state = .completed
                latestMessage = cleaned(payload["last_agent_message"] as? String) ?? latestMessage
                turnCompletedAt = parsedDate(payload["completed_at"]) ?? eventDate
                durationMilliseconds = numericInt64(payload["duration_ms"])
            case "token_count":
                if let info = payload["info"] as? [String: Any],
                   let total = info["total_token_usage"] as? [String: Any],
                   let output = numericInt64(total["output_tokens"]) {
                    if let previousOutput = previousTokenOutput,
                       let previousDate = previousTokenDate,
                       let eventDate {
                        let interval = eventDate.timeIntervalSince(previousDate)
                        let delta = output - previousOutput
                        if interval >= 0.2, interval <= 600, delta > 0 {
                            let rate = Double(delta) / interval
                            if rate < 1_000 { latestTokenRate = rate }
                        }
                    }
                    latestOutput = output
                    previousTokenOutput = output
                    previousTokenDate = eventDate
                }
            case "plan_update", "turn_plan_updated":
                plan = planSteps(from: payload)
            case "background_event":
                let message = (payload["message"] as? String ?? "").lowercased()
                if message.contains("timed out") || message.contains("timeout") { state = .timedOut }
                else if message.contains("reconnect") || message.contains("retry") { state = .reconnecting }
            default: break
            }
        }

        let elapsed: TimeInterval? = {
            guard let start = turnStartedAt else { return nil }
            return (turnCompletedAt ?? latestEventDate ?? Date()).timeIntervalSince(start)
        }()
        let turnAverageSpeed: Double? = {
            guard let latestOutput, let elapsed, elapsed > 0 else { return nil }
            let delta = max(0, latestOutput - (outputAtStart ?? latestOutput))
            return delta > 0 ? Double(delta) / elapsed : nil
        }()
        let details = CodexSessionDetails(
            model: model,
            reasoningEffort: effort,
            outputTokensPerSecond: latestTokenRate ?? turnAverageSpeed,
            latestThinking: latestThinking,
            latestMessage: latestMessage,
            plan: plan,
            question: question,
            turnStartedAt: turnStartedAt,
            turnCompletedAt: turnCompletedAt,
            durationMilliseconds: durationMilliseconds
        )
        return Observation(activity: state, details: details)
    }

    private static func rolloutURLs(
        for threads: [CodexThreadSummary],
        homeDirectory: URL
    ) -> [String: URL] {
        let ids = Set(threads.map(\.id))
        var rollouts: [String: URL] = [:]
        let sessions = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if let id = ids.first(where: { url.lastPathComponent.contains($0) }) {
                    rollouts[id] = url
                    if rollouts.count == ids.count { break }
                }
            }
        }
        return rollouts
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func numericInt64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private static func numericDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func planSteps(from payload: [String: Any]) -> [CodexPlanStep] {
        let values = payload["plan"] as? [[String: Any]] ?? payload["steps"] as? [[String: Any]] ?? []
        return values.compactMap { item in
            guard let text = item["step"] as? String ?? item["text"] as? String else { return nil }
            return CodexPlanStep(text: text, status: item["status"] as? String ?? "pending")
        }
    }

    private static func planSteps(fromToolInput input: String) -> [CodexPlanStep] {
        if let data = input.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let values = planSteps(from: object)
            if !values.isEmpty { return values }
        }

        let pattern = #"\"?(?:step|text)\"?\s*:\s*\"((?:\\.|[^\"\\])*)\"\s*,\s*\"?status\"?\s*:\s*\"([^\"]+)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.matches(in: input, range: range).compactMap { match in
            guard let textRange = Range(match.range(at: 1), in: input),
                  let statusRange = Range(match.range(at: 2), in: input) else { return nil }
            return CodexPlanStep(
                text: decodedJSONString(String(input[textRange])),
                status: String(input[statusRange])
            )
        }
    }

    private static func questionPrompt(fromToolInput input: String) -> CodexQuestionPrompt? {
        if let data = input.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let prompt = questionPrompt(from: object) {
            return prompt
        }

        guard let question = firstJSONString(named: "question", in: input) else { return nil }
        let title = firstJSONString(named: "header", in: input) ?? "Codex question"
        let optionPattern = #"\"?label\"?\s*:\s*\"((?:\\.|[^\"\\])*)\"(?:\s*,\s*\"?description\"?\s*:\s*\"((?:\\.|[^\"\\])*)\")?"#
        let options: [CodexQuestionOption]
        if let expression = try? NSRegularExpression(pattern: optionPattern) {
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            options = expression.matches(in: input, range: range).compactMap { match in
                guard let labelRange = Range(match.range(at: 1), in: input) else { return nil }
                let detail = Range(match.range(at: 2), in: input).map {
                    decodedJSONString(String(input[$0]))
                }
                return CodexQuestionOption(
                    label: decodedJSONString(String(input[labelRange])),
                    detail: detail
                )
            }
        } else {
            options = []
        }
        return CodexQuestionPrompt(title: title, question: question, options: options)
    }

    private static func firstJSONString(named key: String, in input: String) -> String? {
        let pattern = #"\"?"# + NSRegularExpression.escapedPattern(for: key)
            + #"\"?\s*:\s*\"((?:\\.|[^\"\\])*)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = expression.firstMatch(in: input, range: range),
              let valueRange = Range(match.range(at: 1), in: input) else { return nil }
        return decodedJSONString(String(input[valueRange]))
    }

    private static func decodedJSONString(_ value: String) -> String {
        let quoted = "\"\(value)\""
        guard let data = quoted.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else { return value }
        return decoded
    }

    private static func questionPrompt(from payload: [String: Any]) -> CodexQuestionPrompt? {
        let questions = payload["questions"] as? [[String: Any]]
            ?? (payload["params"] as? [String: Any])?["questions"] as? [[String: Any]]
            ?? []
        guard let item = questions.first,
              let question = item["question"] as? String else { return nil }
        let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> CodexQuestionOption? in
            guard let label = option["label"] as? String else { return nil }
            return CodexQuestionOption(label: label, detail: option["description"] as? String)
        }
        return CodexQuestionPrompt(
            title: item["header"] as? String ?? "Codex question",
            question: question,
            options: options
        )
    }
}
