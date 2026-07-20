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
