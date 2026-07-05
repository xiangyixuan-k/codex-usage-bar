import Foundation

enum CurrentModelReader {
    static func read(config: UsageConfig) -> String? {
        for path in SQLiteUsageReader.stateDatabasePaths(config: config) {
            switch SQLiteCommand.run(path: path, query: query) {
            case .success(let output):
                let model = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !model.isEmpty {
                    return model
                }
            case .failure(let message):
                if message.localizedCaseInsensitiveContains("no such column") {
                    continue
                }
            }
        }

        return nil
    }

    private static let query = """
    SELECT model
    FROM threads
    WHERE model IS NOT NULL
      AND TRIM(model) <> ''
    ORDER BY updated_at DESC, id DESC
    LIMIT 1;
    """
}

enum RateLimitNameMatcher {
    static func matches(_ candidate: String?, preferredModel: String?) -> Bool {
        guard let candidate, let preferredModel else {
            return true
        }

        let normalizedCandidate = normalize(candidate)
        let normalizedPreferred = normalize(preferredModel)
        guard !normalizedCandidate.isEmpty, !normalizedPreferred.isEmpty else {
            return true
        }

        return normalizedCandidate == normalizedPreferred
            || normalizedCandidate.contains(normalizedPreferred)
            || normalizedPreferred.contains(normalizedCandidate)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "")
    }
}
