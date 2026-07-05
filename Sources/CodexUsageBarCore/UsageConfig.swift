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

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english
    case simplifiedChinese
}

public struct UsageConfig: Codable, Equatable, Sendable {
    public var codexHome: String
    public var tokenBudget: Int
    public var period: BudgetPeriod
    public var refreshIntervalSeconds: Double
    public var warningRemainingPercent: Double
    public var criticalRemainingPercent: Double
    public var enableOfficialRateLimitSnapshots: Bool
    public var maxRateLimitSnapshotAgeMinutes: Double
    public var rateLimitDisplayWindow: RateLimitWindow
    public var language: AppLanguage
    public var customStateDatabasePaths: [String]
    public var includeArchivedSessionsFallback: Bool

    private enum CodingKeys: String, CodingKey {
        case codexHome
        case tokenBudget
        case period
        case refreshIntervalSeconds
        case warningRemainingPercent
        case criticalRemainingPercent
        case enableOfficialRateLimitSnapshots
        case maxRateLimitSnapshotAgeMinutes
        case rateLimitDisplayWindow
        case language
        case customStateDatabasePaths
        case includeArchivedSessionsFallback
    }

    public init(
        codexHome: String = "~/.codex",
        tokenBudget: Int = 300_000_000,
        period: BudgetPeriod = .monthly,
        refreshIntervalSeconds: Double = 30,
        warningRemainingPercent: Double = 25,
        criticalRemainingPercent: Double = 10,
        enableOfficialRateLimitSnapshots: Bool = true,
        maxRateLimitSnapshotAgeMinutes: Double = 360,
        rateLimitDisplayWindow: RateLimitWindow = .mostConstrained,
        language: AppLanguage = .english,
        customStateDatabasePaths: [String] = [],
        includeArchivedSessionsFallback: Bool = false
    ) {
        self.codexHome = codexHome
        self.tokenBudget = tokenBudget
        self.period = period
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.warningRemainingPercent = warningRemainingPercent
        self.criticalRemainingPercent = criticalRemainingPercent
        self.enableOfficialRateLimitSnapshots = enableOfficialRateLimitSnapshots
        self.maxRateLimitSnapshotAgeMinutes = maxRateLimitSnapshotAgeMinutes
        self.rateLimitDisplayWindow = rateLimitDisplayWindow
        self.language = language
        self.customStateDatabasePaths = customStateDatabasePaths
        self.includeArchivedSessionsFallback = includeArchivedSessionsFallback
    }

    public init(from decoder: Decoder) throws {
        let defaults = UsageConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        codexHome = try container.decodeIfPresent(String.self, forKey: .codexHome) ?? defaults.codexHome
        tokenBudget = try container.decodeIfPresent(Int.self, forKey: .tokenBudget) ?? defaults.tokenBudget
        period = try container.decodeIfPresent(BudgetPeriod.self, forKey: .period) ?? defaults.period
        refreshIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds) ?? defaults.refreshIntervalSeconds
        warningRemainingPercent = try container.decodeIfPresent(Double.self, forKey: .warningRemainingPercent) ?? defaults.warningRemainingPercent
        criticalRemainingPercent = try container.decodeIfPresent(Double.self, forKey: .criticalRemainingPercent) ?? defaults.criticalRemainingPercent
        enableOfficialRateLimitSnapshots = try container.decodeIfPresent(Bool.self, forKey: .enableOfficialRateLimitSnapshots) ?? defaults.enableOfficialRateLimitSnapshots
        maxRateLimitSnapshotAgeMinutes = try container.decodeIfPresent(Double.self, forKey: .maxRateLimitSnapshotAgeMinutes) ?? defaults.maxRateLimitSnapshotAgeMinutes
        rateLimitDisplayWindow = try container.decodeIfPresent(RateLimitWindow.self, forKey: .rateLimitDisplayWindow) ?? defaults.rateLimitDisplayWindow
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? defaults.language
        customStateDatabasePaths = try container.decodeIfPresent([String].self, forKey: .customStateDatabasePaths) ?? defaults.customStateDatabasePaths
        includeArchivedSessionsFallback = try container.decodeIfPresent(Bool.self, forKey: .includeArchivedSessionsFallback) ?? defaults.includeArchivedSessionsFallback
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
        let config = try JSONDecoder().decode(UsageConfig.self, from: data)
        if createIfMissing {
            try? save(config, to: url)
        }
        return config
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
