import Foundation

public struct UsageReadResult: Equatable, Sendable {
    public var usedTokens: Int
    public var threadCount: Int
    public var source: String
    public var warnings: [String]

    public init(usedTokens: Int, threadCount: Int, source: String, warnings: [String] = []) {
        self.usedTokens = usedTokens
        self.threadCount = threadCount
        self.source = source
        self.warnings = warnings
    }
}

public enum UsageReader {
    public static func snapshot(
        config: UsageConfig,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        let startDate = config.period.startDate(now: now, calendar: calendar)
        var warnings: [String] = []

        let rateLimitResult = RateLimitReader.read(config: config, now: now)
        warnings.append(contentsOf: rateLimitResult.warnings)
        if let officialRateLimit = rateLimitResult.snapshot {
            return UsageSnapshot(
                usedTokens: 0,
                tokenBudget: 0,
                threadCount: 0,
                period: config.period,
                source: "official rate_limits: \(officialRateLimit.sourceFile)",
                updatedAt: now,
                warnings: warnings,
                officialRateLimit: officialRateLimit
            )
        }

        let sqliteResult = SQLiteUsageReader.read(config: config, since: startDate)
        warnings.append(contentsOf: sqliteResult.warnings)

        let selectedResult: UsageReadResult
        if sqliteResult.threadCount > 0 || sqliteResult.usedTokens > 0 {
            selectedResult = sqliteResult
        } else {
            let jsonlResult = JSONLUsageReader.read(config: config, since: startDate)
            warnings.append(contentsOf: jsonlResult.warnings)
            selectedResult = jsonlResult.usedTokens > 0 || jsonlResult.threadCount > 0
                ? UsageReadResult(
                    usedTokens: jsonlResult.usedTokens,
                    threadCount: jsonlResult.threadCount,
                    source: jsonlResult.source,
                    warnings: warnings
                )
                : UsageReadResult(
                    usedTokens: 0,
                    threadCount: 0,
                    source: "none",
                    warnings: warnings + ["No Codex usage records were found for \(config.period.label)."]
                )
        }

        return UsageSnapshot(
            usedTokens: selectedResult.usedTokens,
            tokenBudget: config.tokenBudget,
            threadCount: selectedResult.threadCount,
            period: config.period,
            source: selectedResult.source,
            updatedAt: now,
            warnings: selectedResult.warnings.isEmpty ? warnings : selectedResult.warnings
        )
    }
}
