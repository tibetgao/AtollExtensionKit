import XCTest
@testable import CodexQuotaCore

final class CodexQuotaSnapshotTests: XCTestCase {
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
}
