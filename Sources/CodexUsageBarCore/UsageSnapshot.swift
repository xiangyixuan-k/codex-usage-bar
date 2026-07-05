import Foundation

public enum UsageHealth: String, Codable, Sendable {
    case ok
    case warning
    case critical
    case unknown
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var usedTokens: Int
    public var tokenBudget: Int
    public var threadCount: Int
    public var period: BudgetPeriod
    public var source: String
    public var updatedAt: Date
    public var warnings: [String]
    public var officialRateLimit: OfficialRateLimitSnapshot?

    public init(
        usedTokens: Int,
        tokenBudget: Int,
        threadCount: Int,
        period: BudgetPeriod,
        source: String,
        updatedAt: Date = Date(),
        warnings: [String] = [],
        officialRateLimit: OfficialRateLimitSnapshot? = nil
    ) {
        self.usedTokens = max(0, usedTokens)
        self.tokenBudget = max(0, tokenBudget)
        self.threadCount = max(0, threadCount)
        self.period = period
        self.source = source
        self.updatedAt = updatedAt
        self.warnings = warnings
        self.officialRateLimit = officialRateLimit
    }

    public var remainingTokens: Int {
        max(0, tokenBudget - usedTokens)
    }

    public var usedPercent: Double? {
        guard tokenBudget > 0 else {
            return nil
        }
        return min(999, (Double(usedTokens) / Double(tokenBudget)) * 100)
    }

    public var remainingPercent: Double? {
        guard tokenBudget > 0 else {
            return nil
        }
        return max(0, 100 - ((Double(usedTokens) / Double(tokenBudget)) * 100))
    }

    public var displayRemainingPercent: Double? {
        officialRateLimit?.remainingPercent ?? remainingPercent
    }

    public func health(warningRemainingPercent: Double, criticalRemainingPercent: Double) -> UsageHealth {
        guard let remainingPercent = displayRemainingPercent else {
            return .unknown
        }
        if remainingPercent <= criticalRemainingPercent {
            return .critical
        }
        if remainingPercent <= warningRemainingPercent {
            return .warning
        }
        return .ok
    }

    public func menuBarTitle() -> String {
        guard let remainingPercent = displayRemainingPercent else {
            return "--%"
        }
        return "\(Int(remainingPercent.rounded()))%"
    }

    public func compactSummary() -> String {
        if let officialRateLimit, let remaining = officialRateLimit.remainingPercent {
            let name = officialRateLimit.limitName ?? officialRateLimit.limitID ?? "Codex"
            return "\(name): \(Int(remaining.rounded()))% remaining, \(officialRateLimit.resetDescription)"
        }

        let used = Self.format(tokens: usedTokens)
        let budget = tokenBudget > 0 ? Self.format(tokens: tokenBudget) : "not set"
        if let remainingPercent {
            return "\(used) used of \(budget), \(Int(remainingPercent.rounded()))% remaining"
        }
        return "\(used) used; budget \(budget)"
    }

    public static func format(tokens: Int) -> String {
        let value = Double(tokens)
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fk", value / 1_000)
        }
        return "\(tokens)"
    }
}
