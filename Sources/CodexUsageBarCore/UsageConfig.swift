import Foundation

public enum BudgetPeriod: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case rolling24h

    public var label: String {
        switch self {
        case .daily:
            "today"
        case .weekly:
            "this week"
        case .monthly:
            "this month"
        case .rolling24h:
            "last 24h"
        }
    }

    public func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            calendar.startOfDay(for: now)
        case .weekly:
            calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? calendar.startOfDay(for: now)
        case .monthly:
            calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
        case .rolling24h:
            now.addingTimeInterval(-24 * 60 * 60)
        }
    }
}

public struct UsageConfig: Codable, Equatable, Sendable {
    public var codexHome: String
    public var tokenBudget: Int
    public var period: BudgetPeriod
    public var refreshIntervalSeconds: Double
    public var warningRemainingPercent: Double
    public var criticalRemainingPercent: Double
    public var customStateDatabasePaths: [String]
    public var includeArchivedSessionsFallback: Bool

    public init(
        codexHome: String = "~/.codex",
        tokenBudget: Int = 300_000_000,
        period: BudgetPeriod = .monthly,
        refreshIntervalSeconds: Double = 60,
        warningRemainingPercent: Double = 25,
        criticalRemainingPercent: Double = 10,
        customStateDatabasePaths: [String] = [],
        includeArchivedSessionsFallback: Bool = false
    ) {
        self.codexHome = codexHome
        self.tokenBudget = tokenBudget
        self.period = period
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.warningRemainingPercent = warningRemainingPercent
        self.criticalRemainingPercent = criticalRemainingPercent
        self.customStateDatabasePaths = customStateDatabasePaths
        self.includeArchivedSessionsFallback = includeArchivedSessionsFallback
    }
}

public enum ConfigStore {
    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-usage-bar", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public static func load(from url: URL = defaultConfigURL, createIfMissing: Bool = true) throws -> UsageConfig {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            guard createIfMissing else {
                return UsageConfig()
            }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try save(UsageConfig(), to: url)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UsageConfig.self, from: data)
    }

    public static func save(_ config: UsageConfig, to url: URL = defaultConfigURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}

public enum PathExpander {
    public static func expand(_ rawPath: String) -> String {
        if rawPath == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }

        if rawPath.hasPrefix("~/") {
            let suffix = String(rawPath.dropFirst(2))
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(suffix)
                .path
        }

        return (rawPath as NSString).expandingTildeInPath
    }
}
