import XCTest
@testable import CodexQuotaCore

final class CodexQuotaSnapshotTests: XCTestCase {
    func testDashboardBridgeRequiresExactNonEmptyToken() throws {
        let credentials = CodexDashboardBridgeCredentials(token: "expected-token")

        XCTAssertTrue(credentials.authorizes(try XCTUnwrap(
            URLComponents(string: "http://127.0.0.1:9031/dashboard?token=expected-token")
        )))
        XCTAssertFalse(credentials.authorizes(try XCTUnwrap(
            URLComponents(string: "http://127.0.0.1:9031/dashboard")
        )))
        XCTAssertFalse(credentials.authorizes(try XCTUnwrap(
            URLComponents(string: "http://127.0.0.1:9031/dashboard?token=wrong-token")
        )))
        XCTAssertFalse(CodexDashboardBridgeCredentials(token: "").authorizes(try XCTUnwrap(
            URLComponents(string: "http://127.0.0.1:9031/dashboard?token=")
        )))
    }

    func testDecodesRateLimitsAndComputesRemainingQuota() throws {
        let data = Data(#"""
        {
          "rateLimits": {
            "primary": { "usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1730947200 },
            "secondary": { "usedPercent": 80, "windowDurationMins": 10080, "resetsAt": 1731379200 },
            "credits": { "hasCredits": true, "unlimited": false, "balance": "42.5" },
            "planType": "pro",
            "rateLimitReachedType": null,
            "spendControlReached": false
          }
        }
        """#.utf8)

        let result = try JSONDecoder().decode(CodexRateLimitsResult.self, from: data)
        let snapshot = CodexQuotaSnapshot(result: result)

        XCTAssertEqual(snapshot.shortWindow?.remainingPercent, 75)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 20)
        XCTAssertEqual(snapshot.lowestRemainingPercent, 20)
        XCTAssertEqual(snapshot.credits?.balance, "42.5")
        XCTAssertFalse(snapshot.limitReached)
    }

    func testRemainingQuotaIsClamped() {
        let overused = CodexRateLimitWindow(usedPercent: 135, windowDurationMins: 300, resetsAt: 0)
        let negative = CodexRateLimitWindow(usedPercent: -4, windowDurationMins: 300, resetsAt: 0)

        XCTAssertEqual(overused.remainingPercent, 0)
        XCTAssertEqual(negative.remainingPercent, 100)
    }

    func testDecodesThreadPaginationCursor() throws {
        let data = Data(#"""
        {
          "data": [{
            "id": "01234567-89ab-cdef-0123-456789abcdef",
            "name": "Older session",
            "preview": "",
            "cwd": "/tmp",
            "status": { "type": "idle" },
            "modelProvider": "openai",
            "createdAt": 1730947200,
            "updatedAt": 1730947300
          }],
          "nextCursor": "2026-08-28T03:24:17.978Z",
          "backwardsCursor": null
        }
        """#.utf8)

        let result = try JSONDecoder().decode(CodexThreadListResult.self, from: data)

        XCTAssertEqual(result.data.first?.displayName, "Older session")
        XCTAssertEqual(result.nextCursor, "2026-08-28T03:24:17.978Z")
        XCTAssertNil(result.backwardsCursor)
    }

    func testOrphanedRolloutActivityAgesOutOfActiveDashboard() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let staleThread = CodexThreadSummary(
            id: "stale", name: "Stale task", preview: "", cwd: "/tmp",
            status: .notLoaded, modelProvider: "openai",
            createdAt: 1_000_000, updatedAt: 2_000_000 - 7 * 60 * 60
        )
        let freshThread = CodexThreadSummary(
            id: "fresh", name: "Fresh task", preview: "", cwd: "/tmp",
            status: .notLoaded, modelProvider: "openai",
            createdAt: 1_000_000, updatedAt: 2_000_000 - 60
        )
        let snapshot = CodexDashboardSnapshot(
            quota: try emptyQuota(), threads: [staleThread, freshThread],
            activities: ["stale": .running, "fresh": .running]
        )

        XCTAssertEqual(snapshot.activity(for: staleThread, at: now), .disconnected)
        XCTAssertEqual(snapshot.activity(for: freshThread, at: now), .running)
    }

    func testAuthoritativeActiveStatusDoesNotAgeOut() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let thread = CodexThreadSummary(
            id: "active", name: "Long task", preview: "", cwd: "/tmp",
            status: .active(waitingOnApproval: false, waitingOnUserInput: false),
            modelProvider: "openai", createdAt: 1_000_000, updatedAt: 1
        )
        let snapshot = CodexDashboardSnapshot(
            quota: try emptyQuota(), threads: [thread], activities: ["active": .running]
        )

        XCTAssertEqual(snapshot.activity(for: thread, at: now), .running)
    }

    func testActiveSessionIsNotHistoryEligible() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let active = CodexThreadSummary(
            id: "active", name: "Active", preview: "", cwd: "/tmp",
            status: .active(waitingOnApproval: false, waitingOnUserInput: false),
            modelProvider: "openai", createdAt: 1, updatedAt: 2_000_000
        )
        let completed = CodexThreadSummary(
            id: "completed", name: "Completed", preview: "", cwd: "/tmp",
            status: .idle, modelProvider: "openai", createdAt: 1, updatedAt: 2_000_000
        )
        let snapshot = CodexDashboardSnapshot(
            quota: try emptyQuota(), threads: [active, completed],
            activities: ["active": .running, "completed": .completed]
        )

        XCTAssertTrue(snapshot.isActiveSession(active, at: now))
        XCTAssertFalse(snapshot.isActiveSession(completed, at: now))
    }

    func testRecentCompletionIsNotHistoryEligible() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let thread = CodexThreadSummary(
            id: "completed", name: "Completed", preview: "", cwd: "/tmp",
            status: .idle, modelProvider: "openai", createdAt: 1, updatedAt: 2_000_000
        )
        let details = CodexSessionDetails(turnCompletedAt: now.addingTimeInterval(-30))
        let snapshot = CodexDashboardSnapshot(
            quota: try emptyQuota(), threads: [thread], activities: [thread.id: .completed],
            details: [thread.id: details]
        )

        XCTAssertTrue(snapshot.isRecentCompletion(thread, at: now))
        XCTAssertFalse(snapshot.isRecentCompletion(thread, at: now.addingTimeInterval(121)))
    }

    func testReadsNestedPlanQuestionAndRecentTokenSpeedFromRollout() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let threadID = "01234567-89ab-cdef-0123-456789abcdef"
        let sessions = home.appendingPathComponent(".codex/sessions/2026/08/29", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rollout = sessions.appendingPathComponent("rollout-\(threadID).jsonl")
        let lines = [
            #"{"timestamp":"2026-08-29T05:00:00.125Z","type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high"}}"#,
            #"{"timestamp":"2026-08-29T05:00:01.250Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"output_tokens":100}}}}"#,
            #"{"timestamp":"2026-08-29T05:00:02.250Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-08-29T05:00:03.250Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const p = await tools.update_plan({plan:[{step:\"Inspect\",\"status\":\"completed\"},{step:\"Verify\",\"status\":\"in_progress\"}]});"}}"#,
            #"{"timestamp":"2026-08-29T05:00:06.250Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"output_tokens":150}}}}"#,
            #"{"timestamp":"2026-08-29T05:00:07.250Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const r = await tools.request_user_input({questions:[{\"question\":\"Choose?\",\"header\":\"Choice\",options:[{\"label\":\"A\",\"description\":\"First\"},{\"label\":\"B\",\"description\":\"Second\"}]}]});"}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: rollout)
        let thread = CodexThreadSummary(
            id: threadID, name: "Test", preview: "", cwd: "/tmp",
            status: .notLoaded, modelProvider: "openai",
            createdAt: 1, updatedAt: 2
        )

        let observation = try XCTUnwrap(
            LocalCodexActivityMonitor.observations(for: [thread], homeDirectory: home)[threadID]
        )
        XCTAssertEqual(observation.activity, .waitingForInput)
        XCTAssertEqual(observation.details.model, "gpt-5.6-sol")
        XCTAssertEqual(observation.details.reasoningEffort, "high")
        XCTAssertEqual(try XCTUnwrap(observation.details.outputTokensPerSecond), 10, accuracy: 0.001)
        XCTAssertEqual(observation.details.plan.map(\.text), ["Inspect", "Verify"])
        XCTAssertEqual(observation.details.question?.question, "Choose?")
        XCTAssertEqual(observation.details.question?.options.map(\.label), ["A", "B"])
    }

    private func emptyQuota() throws -> CodexQuotaSnapshot {
        let data = Data(#"{"rateLimits":{}}"#.utf8)
        return CodexQuotaSnapshot(result: try JSONDecoder().decode(CodexRateLimitsResult.self, from: data))
    }
}
