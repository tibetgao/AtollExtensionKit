import Foundation

/// Provider boundary reserved for additional VibeIsland-style agent integrations.
public protocol AgentMonitoringProvider: Sendable {
    associatedtype Snapshot: Codable & Equatable & Sendable
    var providerID: String { get }
    var capabilities: Set<AgentCapability> { get }
    func refresh() async throws -> Snapshot
    func events() -> AsyncStream<AgentMonitorEvent>
}

public enum AgentCapability: String, Codable, Hashable, Sendable {
    case sessionOverview
    case approvals
    case questions
    case planReview
    case usage
    case terminalNavigation
    case sessionNavigation
    case sounds
    case remoteSessions
}

public struct AgentMonitorEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let providerID: String
    public let sessionID: String
    public let state: String
    public let occurredAt: Date
    public let action: AgentActionRequest?

    public init(
        id: String,
        providerID: String,
        sessionID: String,
        state: String,
        occurredAt: Date = Date(),
        action: AgentActionRequest? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.sessionID = sessionID
        self.state = state
        self.occurredAt = occurredAt
        self.action = action
    }
}

public enum AgentNavigationTarget: Codable, Equatable, Sendable {
    case usage
    case session(providerID: String, sessionID: String)
    case terminal(providerID: String, sessionID: String)
}

public protocol AgentNavigationRouting: Sendable {
    func open(_ target: AgentNavigationTarget) async throws
}

public protocol AgentActionHandling: Sendable {
    func resolve(requestID: String, response: AgentActionResponse) async throws
}

public enum AgentActionResponse: Codable, Equatable, Sendable {
    case approve
    case deny
    case answer(optionID: String?, text: String?)
}

public struct AgentActionRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let providerID: String
    public let sessionID: String
    public let title: String
    public let detail: String?
    public let options: [AgentActionOption]

    public init(
        id: String,
        providerID: String,
        sessionID: String,
        title: String,
        detail: String? = nil,
        options: [AgentActionOption] = []
    ) {
        self.id = id
        self.providerID = providerID
        self.sessionID = sessionID
        self.title = title
        self.detail = detail
        self.options = options
    }
}

public struct AgentActionOption: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}
