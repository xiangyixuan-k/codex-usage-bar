import Foundation

public enum CodexHeaderRateLimitReader {
    public static func read(
        config: UsageConfig,
        preferredModel: String?,
        now: Date = Date()
    ) -> OfficialRateLimitReadResult {
        guard config.enableOfficialRateLimitSnapshots else {
            return OfficialRateLimitReadResult(snapshot: nil)
        }

        let databasePaths = logDatabasePaths(config: config)
        guard !databasePaths.isEmpty else {
            return OfficialRateLimitReadResult(
                snapshot: nil,
                warnings: ["No Codex request log database was found under \(PathExpander.expand(config.codexHome))."]
            )
        }

        let maxAgeSeconds = config.maxRateLimitSnapshotAgeMinutes * 60
        let modifiedSince = now.addingTimeInterval(-maxAgeSeconds)
        var candidates: [Candidate] = []
        var warnings: [String] = []

        for path in databasePaths.prefix(3) {
            switch SQLiteCommand.run(path: path, query: query, separator: columnSeparator) {
            case .success(let output):
                candidates.append(contentsOf: parseRows(
                    output,
                    databaseName: (path as NSString).lastPathComponent,
                    displayWindow: config.rateLimitDisplayWindow,
                    modifiedSince: modifiedSince,
                    fallbackModel: preferredModel
                ))
            case .failure(let message):
                warnings.append("\((path as NSString).lastPathComponent): \(message)")
            }
        }

        guard !candidates.isEmpty else {
            warnings.append("No recent Codex response-header rate limit was found.")
            return OfficialRateLimitReadResult(snapshot: nil, warnings: warnings)
        }

        if let preferredModel {
            let matching = candidates.filter { RateLimitNameMatcher.matches($0.modelName, preferredModel: preferredModel) }
            if let best = newest(matching) {
                return OfficialRateLimitReadResult(snapshot: best.snapshot, warnings: warnings)
            }

            if candidates.contains(where: { $0.modelName != nil }) {
                warnings.append("No recent Codex response-header rate limit matched current model \(preferredModel).")
                return OfficialRateLimitReadResult(snapshot: nil, warnings: warnings)
            }
        }

        return OfficialRateLimitReadResult(snapshot: newest(candidates)?.snapshot, warnings: warnings)
    }

    private struct Candidate {
        var snapshot: OfficialRateLimitSnapshot
        var modelName: String?
    }

    private static let columnSeparator = "\u{1F}"

    private static let query = """
    SELECT ts,
           substr(replace(replace(COALESCE(feedback_log_body, ''), char(10), ' '), char(13), ' '), 1, 300)
           || ' '
           || substr(
               replace(replace(COALESCE(feedback_log_body, ''), char(10), ' '), char(13), ' '),
               max(1, instr(feedback_log_body, 'headers=') - 80),
               2600
           )
    FROM logs
    WHERE feedback_log_body LIKE '%x-codex-primary-used-percent%'
    ORDER BY ts DESC, ts_nanos DESC, id DESC
    LIMIT 80;
    """

    private static func parseRows(
        _ output: String,
        databaseName: String,
        displayWindow: RateLimitWindow,
        modifiedSince: Date,
        fallbackModel: String?
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        let separatorCharacter: Character = "\u{1F}"

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: separatorCharacter, maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let timestamp = TimeInterval(String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                continue
            }

            let observedAt = Date(timeIntervalSince1970: timestamp)
            guard observedAt >= modifiedSince else {
                continue
            }

            let body = String(parts[1])
            guard let candidate = parseBody(
                body,
                observedAt: observedAt,
                databaseName: databaseName,
                displayWindow: displayWindow,
                fallbackModel: fallbackModel
            ) else {
                continue
            }

            candidates.append(candidate)
        }

        return candidates
    }

    private static func parseBody(
        _ body: String,
        observedAt: Date,
        databaseName: String,
        displayWindow: RateLimitWindow,
        fallbackModel: String?
    ) -> Candidate? {
        let headers = parseHeaders(body)
        guard let primaryUsed = doubleHeader("x-codex-primary-used-percent", headers: headers) else {
            return nil
        }

        let secondaryUsed = doubleHeader("x-codex-secondary-used-percent", headers: headers)
        let primary = RateLimitWindowSnapshot(
            usedPercent: primaryUsed,
            windowMinutes: intHeader("x-codex-primary-window-minutes", headers: headers),
            resetsAt: resetDate(prefix: "x-codex-primary", headers: headers, observedAt: observedAt)
        )
        let secondary = secondaryUsed.map {
            RateLimitWindowSnapshot(
                usedPercent: $0,
                windowMinutes: intHeader("x-codex-secondary-window-minutes", headers: headers),
                resetsAt: resetDate(prefix: "x-codex-secondary", headers: headers, observedAt: observedAt)
            )
        }

        let model = modelName(in: body)
        let activeLimit = stringHeader("x-codex-active-limit", headers: headers)
        let planType = stringHeader("x-codex-plan-type", headers: headers)
        let displayName = model ?? fallbackModel ?? "Codex"

        return Candidate(
            snapshot: OfficialRateLimitSnapshot(
                limitID: activeLimit ?? planType,
                limitName: displayName,
                primary: primary,
                secondary: secondary,
                displayWindow: displayWindow,
                observedAt: observedAt,
                sourceFile: databaseName
            ),
            modelName: model
        )
    }

    private static func parseHeaders(_ body: String) -> [String: String] {
        guard let payload = headersPayload(in: body) else {
            return [:]
        }

        if let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: [:]) { result, item in
                result[item.key.lowercased()] = stringValue(item.value)
            }
        }

        return parseQuotedHeaders(payload)
    }

    private static func headersPayload(in body: String) -> String? {
        guard let marker = body.range(of: "headers=") else {
            return nil
        }

        var start = marker.upperBound
        while start < body.endIndex, body[start] != "{" {
            start = body.index(after: start)
        }

        guard start < body.endIndex else {
            return nil
        }

        var index = start
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while index < body.endIndex {
            let character = body[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(body[start...index])
                }
            }

            index = body.index(after: index)
        }

        return String(body[start...])
    }

    private static func parseQuotedHeaders(_ payload: String) -> [String: String] {
        let pattern = #""([^"]+)"\s*:\s*"([^"]*)""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
        return expression.matches(in: payload, range: range).reduce(into: [:]) { result, match in
            guard match.numberOfRanges == 3,
                  let keyRange = Range(match.range(at: 1), in: payload),
                  let valueRange = Range(match.range(at: 2), in: payload) else {
                return
            }

            result[String(payload[keyRange]).lowercased()] = String(payload[valueRange])
        }
    }

    private static func stringHeader(_ name: String, headers: [String: String]) -> String? {
        headers[name.lowercased()]
    }

    private static func doubleHeader(_ name: String, headers: [String: String]) -> Double? {
        stringHeader(name, headers: headers).flatMap(Double.init)
    }

    private static func intHeader(_ name: String, headers: [String: String]) -> Int? {
        doubleHeader(name, headers: headers).map(Int.init)
    }

    private static func resetDate(prefix: String, headers: [String: String], observedAt: Date) -> Date? {
        if let resetAt = stringHeader("\(prefix)-reset-at", headers: headers),
           let date = parseHeaderDate(resetAt) {
            return date
        }

        if let resetAfter = doubleHeader("\(prefix)-reset-after-seconds", headers: headers) {
            return observedAt.addingTimeInterval(resetAfter)
        }

        return nil
    }

    private static func parseHeaderDate(_ value: String) -> Date? {
        if let timestamp = Double(value) {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func modelName(in body: String) -> String? {
        if let value = token(after: "model=", in: body) {
            return value
        }

        if let range = body.range(of: #""model"\s*:\s*""#, options: .regularExpression) {
            let rest = body[range.upperBound...]
            let value = rest.prefix { $0 != "\"" }
            if !value.isEmpty {
                return String(value)
            }
        }

        return nil
    }

    private static func token(after marker: String, in body: String) -> String? {
        guard let range = body.range(of: marker) else {
            return nil
        }

        let delimiters: Set<Character> = [" ", "\t", "\n", "\r", ",", "}", "]", ")"]
        let rest = body[range.upperBound...]
        let rawValue = rest.prefix { !delimiters.contains($0) }
        let value = String(rawValue).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return value.isEmpty ? nil : String(value)
    }

    private static func stringValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return "\(value)"
        }
    }

    private static func newest(_ candidates: [Candidate]) -> Candidate? {
        candidates.max { lhs, rhs in
            lhs.snapshot.observedAt < rhs.snapshot.observedAt
        }
    }

    private static func logDatabasePaths(config: UsageConfig) -> [String] {
        let fileManager = FileManager.default
        let codexHome = URL(fileURLWithPath: PathExpander.expand(config.codexHome), isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("logs")
                    && name.hasSuffix(".sqlite")
                    && !name.hasSuffix("-wal")
                    && !name.hasSuffix("-shm")
            }
            .sorted { modificationDate($0) > modificationDate($1) }
            .map(\.path)
    }

    private static func modificationDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }
}
