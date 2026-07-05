import Foundation

public enum SQLiteUsageReader {
    public static func read(config: UsageConfig, since startDate: Date) -> UsageReadResult {
        let databasePaths = stateDatabasePaths(config: config)
        guard !databasePaths.isEmpty else {
            return UsageReadResult(
                usedTokens: 0,
                threadCount: 0,
                source: "sqlite",
                warnings: ["No Codex state database found under \(PathExpander.expand(config.codexHome))."]
            )
        }

        var usedTokens = 0
        var threadCount = 0
        var warnings: [String] = []
        let startMillis = Int64(startDate.timeIntervalSince1970 * 1000)
        let query = """
        SELECT COALESCE(SUM(tokens_used), 0), COUNT(*)
        FROM threads
        WHERE COALESCE(created_at_ms, created_at * 1000) >= \(startMillis);
        """

        for path in databasePaths {
            switch SQLiteCommand.run(path: path, query: query) {
            case .success(let output):
                let parsed = parseSQLiteSum(output)
                usedTokens += parsed.usedTokens
                threadCount += parsed.threadCount
            case .failure(let message):
                warnings.append("\((path as NSString).lastPathComponent): \(message)")
            }
        }

        let sourceNames = databasePaths
            .map { ($0 as NSString).lastPathComponent }
            .joined(separator: ", ")

        return UsageReadResult(
            usedTokens: usedTokens,
            threadCount: threadCount,
            source: "sqlite: \(sourceNames)",
            warnings: warnings
        )
    }

    public static func stateDatabasePaths(config: UsageConfig) -> [String] {
        let fileManager = FileManager.default
        if !config.customStateDatabasePaths.isEmpty {
            return config.customStateDatabasePaths
                .map(PathExpander.expand)
                .filter { fileManager.fileExists(atPath: $0) }
        }

        let codexHome = PathExpander.expand(config.codexHome)
        var candidates: [URL] = []
        let roots = [
            URL(fileURLWithPath: codexHome, isDirectory: true),
            URL(fileURLWithPath: codexHome, isDirectory: true).appendingPathComponent("sqlite", isDirectory: true)
        ]

        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            candidates.append(contentsOf: entries.filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("state_")
                    && name.hasSuffix(".sqlite")
                    && !name.hasSuffix("-wal")
                    && !name.hasSuffix("-shm")
            })
        }

        guard let newest = candidates.max(by: { lhs, rhs in
            modificationDate(lhs) < modificationDate(rhs)
        }) else {
            return []
        }

        return [newest.path]
    }

    private static func modificationDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private static func parseSQLiteSum(_ output: String) -> (usedTokens: Int, threadCount: Int) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return (0, 0)
        }
        return (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
    }
}
