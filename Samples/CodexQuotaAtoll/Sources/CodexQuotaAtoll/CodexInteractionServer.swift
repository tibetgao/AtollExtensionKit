import AppKit
import CodexQuotaCore
import Foundation
import Network

/// A loopback-only bridge used by Atoll's sandboxed web view.
///
/// Keeping navigation outside the HTML lets the dashboard remain fully local
/// while still using the public Codex deep-link surface.
final class CodexInteractionServer: @unchecked Sendable {
    static let port: NWEndpoint.Port = 9_031

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.tibetgao.CodexQuotaAtoll.navigation")
    private let preferences: CodexDashboardPreferences
    private var snapshot: CodexDashboardSnapshot?

    init(preferences: CodexDashboardPreferences) {
        self.preferences = preferences
    }

    func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func update(snapshot: CodexDashboardSnapshot) {
        queue.sync {
            self.snapshot = snapshot
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let firstLine = request.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            let components = firstLine.split(separator: " ")
            let method = components.first.map(String.init) ?? ""
            let target = components.count > 1 ? String(components[1]) : "/"
            let response: HTTPResponse
            if method == "OPTIONS" {
                response = .noContent
            } else if method == "GET", let handled = self.handle(target: target) {
                response = handled
            } else {
                response = .notFound
            }
            connection.send(content: response.encoded, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func handle(target: String) -> HTTPResponse? {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else { return nil }
        let destination: URL?
        switch components.path {
        case "/dashboard":
            return dashboardResponse()
        case "/sessions":
            return sessionsResponse(components)
        case "/open/quota":
            // The desktop app does not expose a public Usage deep link. This
            // official web settings route opens the Usage and billing pane.
            destination = URL(string: "https://chatgpt.com/#settings/Usage")
        case "/open/thread":
            let id = components.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            guard Self.isValidThreadID(id) else { return nil }
            destination = URL(string: "codex://threads/\(id)")
        case "/answer":
            let id = components.queryItems?.first(where: { $0.name == "thread" })?.value ?? ""
            let value = components.queryItems?.first(where: { $0.name == "value" })?.value ?? ""
            guard Self.isValidThreadID(id), !value.isEmpty, value.count <= 500 else { return nil }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                if let url = URL(string: "codex://threads/\(id)") {
                    NSWorkspace.shared.open(url)
                }
            }
            return .noContent
        case "/settings/accent":
            let value = components.queryItems?.first(where: { $0.name == "value" })?.value ?? ""
            guard let theme = CodexAccentTheme(rawValue: value) else { return nil }
            preferences.accentTheme = theme
            return .noContent
        case "/settings/font":
            let value = components.queryItems?.first(where: { $0.name == "value" })?.value ?? ""
            guard let size = CodexDashboardTextSize(rawValue: value) else { return nil }
            preferences.textSize = size
            return .noContent
        default:
            return nil
        }

        guard let destination else { return nil }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(destination)
        }
        return .noContent
    }

    private func sessionsResponse(_ components: URLComponents) -> HTTPResponse {
        let query = components.queryItems ?? []
        let offset = max(0, Int(query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0)
        let limit = max(1, min(20, Int(query.first(where: { $0.name == "limit" })?.value ?? "5") ?? 5))
        let threads = snapshot?.threads ?? []
        let start = min(offset, threads.count)
        let end = min(start + limit, threads.count)
        let items: [[String: Any]] = threads[start..<end].map { thread in
            var item: [String: Any] = [
                "id": thread.id,
                "title": thread.displayName,
                "state": snapshot?.activity(for: thread).rawValue ?? CodexTaskActivity.idle.rawValue,
                "updatedAt": thread.updatedAt,
            ]
            if let details = snapshot?.details(for: thread) {
                if let model = details.model { item["model"] = model }
                if let effort = details.reasoningEffort { item["effort"] = effort }
                if let speed = details.outputTokensPerSecond { item["speed"] = speed }
            }
            return item
        }
        let object: [String: Any] = ["items": items, "total": threads.count]
        guard let body = try? JSONSerialization.data(withJSONObject: object) else {
            return .serverError
        }
        return HTTPResponse(status: "200 OK", contentType: "application/json", body: body)
    }

    private func dashboardResponse() -> HTTPResponse {
        guard let snapshot else {
            return jsonResponse(["active": [], "threadCount": 0])
        }
        let activeThreads = snapshot.threads.filter {
            switch snapshot.activity(for: $0) {
            case .preparing, .running, .waitingForApproval, .waitingForInput, .reconnecting:
                return true
            default:
                return false
            }
        }
        let quotaObject: (CodexRateLimitWindow?) -> [String: Any]? = { window in
            guard let window else { return nil }
            return [
                "label": snapshot.quota.label(for: window),
                "remaining": window.remainingPercent,
                "resetsAt": window.resetsAt,
            ]
        }
        var quota: [String: Any] = [:]
        if let primary = quotaObject(snapshot.quota.shortWindow) { quota["primary"] = primary }
        if let secondary = quotaObject(snapshot.quota.weeklyWindow) { quota["secondary"] = secondary }
        let active = activeThreads.map { threadObject($0, snapshot: snapshot, includeDetails: true) }
        let completion = snapshot.threads.first(where: { thread in
            guard snapshot.activity(for: thread) == .completed,
                  let date = snapshot.details(for: thread)?.turnCompletedAt else { return false }
            return Date().timeIntervalSince(date) < 120
        }).map { threadObject($0, snapshot: snapshot, includeDetails: true) }
        var object: [String: Any] = [
            "quota": quota,
            "active": active,
            "threadCount": snapshot.threads.count,
            "refreshedAt": Int64(snapshot.refreshedAt.timeIntervalSince1970),
        ]
        if let completion { object["completion"] = completion }
        return jsonResponse(object)
    }

    private func threadObject(
        _ thread: CodexThreadSummary,
        snapshot: CodexDashboardSnapshot,
        includeDetails: Bool
    ) -> [String: Any] {
        var item: [String: Any] = [
            "id": thread.id,
            "title": thread.displayName,
            "state": snapshot.activity(for: thread).rawValue,
            "updatedAt": thread.updatedAt,
        ]
        guard includeDetails, let details = snapshot.details(for: thread) else { return item }
        if let model = details.model { item["model"] = model }
        if let effort = details.reasoningEffort { item["effort"] = effort }
        if let speed = details.outputTokensPerSecond { item["speed"] = speed }
        if let thinking = details.latestThinking { item["thinking"] = thinking }
        if let message = details.latestMessage { item["message"] = message }
        if let started = details.turnStartedAt { item["startedAt"] = Int64(started.timeIntervalSince1970) }
        if let completed = details.turnCompletedAt { item["completedAt"] = Int64(completed.timeIntervalSince1970) }
        if let duration = details.durationMilliseconds { item["durationMs"] = duration }
        item["plan"] = details.plan.map { ["text": $0.text, "status": $0.status] }
        if let question = details.question {
            item["question"] = [
                "title": question.title,
                "text": question.question,
                "options": question.options.map { ["label": $0.label, "detail": $0.detail ?? ""] },
            ]
        }
        return item
    }

    private func jsonResponse(_ object: [String: Any]) -> HTTPResponse {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return .serverError }
        return HTTPResponse(status: "200 OK", contentType: "application/json", body: body)
    }

    private static func isValidThreadID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) != nil
    }
}

private struct HTTPResponse {
    let status: String
    let contentType: String?
    let body: Data

    static let noContent = HTTPResponse(status: "204 No Content", contentType: nil, body: Data())
    static let notFound = HTTPResponse(status: "404 Not Found", contentType: nil, body: Data())
    static let serverError = HTTPResponse(status: "500 Internal Server Error", contentType: nil, body: Data())

    var encoded: Data {
        var headers = "HTTP/1.1 \(status)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\n"
        if let contentType {
            headers += "Content-Type: \(contentType); charset=utf-8\r\n"
        }
        headers += "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
        var data = Data(headers.utf8)
        data.append(body)
        return data
    }
}
