import Foundation

/// Per-process credentials for the loopback dashboard bridge.
///
/// Loopback binding prevents remote access, while this token prevents unrelated
/// local web content from reading session metadata or invoking dashboard actions.
public struct CodexDashboardBridgeCredentials: Equatable, Sendable {
    public let token: String

    public init(token: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()) {
        self.token = token
    }

    public func authorizes(_ components: URLComponents) -> Bool {
        guard !token.isEmpty else { return false }
        return components.queryItems?.contains {
            $0.name == "token" && $0.value == token
        } == true
    }
}
