import Foundation

public enum JSONLUsageReader {
    public static func read(config: UsageConfig, since startDate: Date) -> UsageReadResult {
        let codexHome = URL(fileURLWithPath: PathExpander.expand(config.codexHome), isDirectory: true)
        var roots = [
            codexHome.appendingPathComponent("sessions", isDirectory: true)
        ]

        if config.includeArchivedSessionsFallback {
            roots.append(codexHome.appendingPathComponent("archived_sessions", isDirectory: true))
        }

        var usedTokens = 0
        var eventCount = 0
        var warnings: [String] = []

        for file in jsonlFiles(under: roots, since: startDate) {
            do {
                let data = try Data(contentsOf: file)
                guard let text = String(data: data, encoding: .utf8) else {
                    warnings.append("\(file.lastPathComponent): not UTF-8")
                    continue
                }

                for line in text.split(separator: "\n") {
                    guard let tokens = usageTokens(in: String(line)) else {
                        continue
                    }
                    usedTokens += tokens
                    eventCount += 1
                }
            } catch {
                warnings.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return UsageReadResult(
            usedTokens: usedTokens,
            threadCount: eventCount,
            source: "jsonl fallback",
            warnings: warnings
        )
    }

    public static func usageTokens(in jsonLine: String) -> Int? {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return collectUsageTokens(from: object).first
    }

    private static func collectUsageTokens(from value: Any) -> [Int] {
        if let dictionary = value as? [String: Any] {
            if let usage = dictionary["usage"] as? [String: Any],
               let tokens = tokenCount(fromUsageDictionary: usage) {
                return [tokens]
            }

            return dictionary.values.flatMap { collectUsageTokens(from: $0) }
        }

        if let array = value as? [Any] {
            return array.flatMap { collectUsageTokens(from: $0) }
        }

        return []
    }

    private static func tokenCount(fromUsageDictionary usage: [String: Any]) -> Int? {
        if let total = integerValue(usage["total_tokens"]) {
            return total
        }

        let input = integerValue(usage["input_tokens"]) ?? integerValue(usage["prompt_tokens"]) ?? 0
        let output = integerValue(usage["output_tokens"]) ?? integerValue(usage["completion_tokens"]) ?? 0
        let total = input + output
        return total > 0 ? total : nil
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func jsonlFiles(under roots: [URL], since startDate: Date) -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let file as URL in enumerator {
                guard file.pathExtension == "jsonl" else {
                    continue
                }

                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true else {
                    continue
                }

                if let modified = values?.contentModificationDate, modified < startDate {
                    continue
                }

                files.append(file)
            }
        }

        return files
    }
}
