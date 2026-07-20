import Foundation

public enum CodexAppServerError: LocalizedError {
    case notRunning
    case serverExited(Int32)
    case invalidMessage
    case rpc(code: Int?, message: String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "codex app-server is not running"
        case .serverExited(let status):
            return "codex app-server exited with status \(status)"
        case .invalidMessage:
            return "codex app-server returned an invalid JSON-RPC message"
        case .rpc(let code, let message):
            return "codex app-server error\(code.map { " \($0)" } ?? ""): \(message)"
        }
    }
}

public actor CodexAppServerClient {
    private let executableURL: URL
    private let environment: [String: String]
    private var process: Process?
    private var input: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executableURL = executableURL
        self.environment = environment
    }

    deinit {
        readerTask?.cancel()
        process?.terminate()
    }

    public func start() async throws {
        guard process == nil else { return }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["codex", "app-server"]
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError
        try process.run()

        self.process = process
        input = stdinPipe.fileHandleForWriting
        let output = stdoutPipe.fileHandleForReading
        readerTask = Task.detached { [weak self, weak process] in
            var buffer = Data()
            while !Task.isCancelled {
                let chunk = output.availableData
                guard !chunk.isEmpty else { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    await self?.handleMessage(Data(line))
                }
            }

            await self?.readerFailed(CodexAppServerError.serverExited(
                process?.terminationStatus ?? -1
            ))
        }

        struct InitializeResult: Decodable {}
        let _: InitializeResult = try await request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "codex_quota_atoll",
                    "title": "Codex Quota for Atoll",
                    "version": "0.1.0",
                ],
            ]
        )
        try sendNotification(method: "initialized")
    }

    public func readRateLimits() async throws -> CodexRateLimitsResult {
        try await start()
        return try await request(method: "account/rateLimits/read")
    }

    public func stop() {
        readerTask?.cancel()
        readerTask = nil
        input?.closeFile()
        input = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        failPending(with: CodexAppServerError.notRunning)
    }

    private func request<Result: Decodable>(
        method: String,
        params: [String: Any]? = nil
    ) async throws -> Result {
        guard process?.isRunning == true, let input else {
            throw CodexAppServerError.notRunning
        }

        let id = nextRequestID
        nextRequestID += 1
        var message: [String: Any] = ["method": method, "id": id]
        if let params { message["params"] = params }
        let payload = try Self.encodedLine(message)

        let resultData = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            pending[id] = continuation
            do {
                try input.write(contentsOf: payload)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
        return try JSONDecoder().decode(Result.self, from: resultData)
    }

    private func sendNotification(method: String) throws {
        guard let input else { throw CodexAppServerError.notRunning }
        try input.write(contentsOf: Self.encodedLine(["method": method]))
    }

    private func handleMessage(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? Int,
            let continuation = pending.removeValue(forKey: id)
        else { return }

        if let error = object["error"] as? [String: Any] {
            continuation.resume(throwing: CodexAppServerError.rpc(
                code: error["code"] as? Int,
                message: error["message"] as? String ?? "Unknown error"
            ))
            return
        }

        guard let result = object["result"],
              let resultData = try? JSONSerialization.data(withJSONObject: result)
        else {
            continuation.resume(throwing: CodexAppServerError.invalidMessage)
            return
        }
        continuation.resume(returning: resultData)
    }

    private func readerFailed(_ error: Error) {
        failPending(with: error)
    }

    private func failPending(with error: Error) {
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private static func encodedLine(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }
}
