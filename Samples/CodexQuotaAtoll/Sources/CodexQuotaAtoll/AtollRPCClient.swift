import AtollExtensionKit
import Foundation

actor AtollRPCClient {
    static let bundleIdentifier = "com.tibetgao.CodexQuotaAtoll"

    private let endpoint = URL(string: "ws://127.0.0.1:9020")!
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var nextID = 1

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    func requestAuthorization() async throws -> Bool {
        let result = try await call(
            method: "atoll.requestAuthorization",
            params: ["bundleIdentifier": Self.bundleIdentifier]
        )
        return result["authorized"] as? Bool ?? false
    }

    func present(_ descriptor: AtollLiveActivityDescriptor) async throws {
        try await sendDescriptor(descriptor, method: "atoll.presentLiveActivity")
    }

    func update(_ descriptor: AtollLiveActivityDescriptor) async throws {
        try await sendDescriptor(descriptor, method: "atoll.updateLiveActivity")
    }

    func dismiss(activityID: String) async throws {
        _ = try await call(
            method: "atoll.dismissLiveActivity",
            params: [
                "activityID": activityID,
                "bundleIdentifier": Self.bundleIdentifier,
            ]
        )
    }

    func close() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session.invalidateAndCancel()
    }

    private func sendDescriptor(
        _ descriptor: AtollLiveActivityDescriptor,
        method: String
    ) async throws {
        let encoded = try JSONEncoder().encode(descriptor)
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw AtollRPCError.invalidDescriptor
        }
        _ = try await call(method: method, params: ["descriptor": object])
    }

    private func call(method: String, params: [String: Any]) async throws -> [String: Any] {
        let task = connectedSocket()
        let id = String(nextID)
        nextID += 1

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        try await task.send(.data(data))

        let message = try await task.receive()
        let responseData: Data
        switch message {
        case .data(let data):
            responseData = data
        case .string(let string):
            responseData = Data(string.utf8)
        @unknown default:
            throw AtollRPCError.invalidResponse
        }

        guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AtollRPCError.invalidResponse
        }
        if let error = response["error"] as? [String: Any] {
            throw AtollRPCError.remote(
                code: error["code"] as? Int ?? -1,
                message: error["message"] as? String ?? "Unknown Atoll RPC error"
            )
        }
        guard response["id"] as? String == id,
              let result = response["result"] as? [String: Any] else {
            throw AtollRPCError.invalidResponse
        }
        return result
    }

    private func connectedSocket() -> URLSessionWebSocketTask {
        if let socket { return socket }
        let task = session.webSocketTask(with: endpoint)
        task.resume()
        socket = task
        return task
    }
}

enum AtollRPCError: LocalizedError {
    case invalidDescriptor
    case invalidResponse
    case remote(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidDescriptor:
            return "Could not encode the Atoll live activity descriptor."
        case .invalidResponse:
            return "Atoll returned an invalid RPC response."
        case .remote(let code, let message):
            return "Atoll RPC error \(code): \(message)"
        }
    }
}
