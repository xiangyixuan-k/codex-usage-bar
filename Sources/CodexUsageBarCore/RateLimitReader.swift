import Foundation

public enum RateLimitWindow: String, Codable, Sendable {
    case primary
    case secondary
    case mostConstrained
}

public struct RateLimitWindowSnapshot: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int?
    public var resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

public struct OfficialRateLimitSnapshot: Codable, Equatable, Sendable {
    public var limitID: String?
    public var limitName: String?
    public var primary: RateLimitWindowSnapshot?
    public var secondary: RateLimitWindowSnapshot?
    public var displayWindow: RateLimitWindow
    public var observedAt: Date
    public var sourceFile: String

    public init(
        limitID: String?,
        limitName: String?,
        primary: RateLimitWindowSnapshot?,
        secondary: RateLimitWindowSnapshot?,
        displayWindow: RateLimitWindow,
        observedAt: Date,
        sourceFile: String
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.displayWindow = displayWindow
        self.observedAt = observedAt
        self.sourceFile = sourceFile
    }

    public var remainingPercent: Double? {
        switch displayWindow {
        case .primary:
            primary?.remainingPercent ?? secondary?.remainingPercent
        case .secondary:
            secondary?.remainingPercent ?? primary?.remainingPercent
        case .mostConstrained:
            [primary?.remainingPercent, secondary?.remainingPercent]
                .compactMap { $0 }
                .min()
        }
    }

    public var resetDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        let resets = [primary?.resetsAt, secondary?.resetsAt].compactMap { $0 }.min()
        guard let resets else {
            return "reset unknown"
        }
        return "resets \(formatter.localizedString(for: resets, relativeTo: Date()))"
    }
}

public struct OfficialRateLimitReadResult: Sendable {
    public var snapshot: OfficialRateLimitSnapshot?
    public var warnings: [String]

    public init(snapshot: OfficialRateLimitSnapshot?, warnings: [String] = []) {
        self.snapshot = snapshot
        self.warnings = warnings
    }
}

public enum RateLimitReader {
    public static func read(config: UsageConfig, now: Date = Date()) -> OfficialRateLimitReadResult {
        guard config.enableOfficialRateLimitSnapshots else {
            return OfficialRateLimitReadResult(snapshot: nil)
        }

        let codexHome = URL(fileURLWithPath: PathExpander.expand(config.codexHome), isDirectory: true)
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        let maxAgeSeconds = config.maxRateLimitSnapshotAgeMinutes * 60
        let modifiedSince = now.addingTimeInterval(-maxAgeSeconds)

        let files = jsonlFiles(under: sessionsRoot, modifiedSince: modifiedSince)
        guard !files.isEmpty else {
            return OfficialRateLimitReadResult(
                snapshot: nil,
                warnings: ["No recent Codex session files were found for official rate-limit snapshots."]
            )
        }

        var best: OfficialRateLimitSnapshot?
        var warnings: [String] = []

        for file in files {
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                for line in text.split(separator: "\n") where line.contains("\"rate_limits\"") {
                    guard let snapshot = parseRateLimitLine(
                        String(line),
                        displayWindow: config.rateLimitDisplayWindow,
                        sourceFile: file.lastPathComponent
                    ) else {
                        continue
                    }
                    guard snapshot.observedAt >= modifiedSince else {
                        continue
                    }

                    if best == nil || snapshot.observedAt > best!.observedAt {
                        best = snapshot
                    }
                }
            } catch {
                warnings.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if best == nil {
            warnings.append("No official rate-limit payload was found in recent Codex sessions.")
        }

        return OfficialRateLimitReadResult(snapshot: best, warnings: warnings)
    }

    public static func parseRateLimitLine(
        _ jsonLine: String,
        displayWindow: RateLimitWindow,
        sourceFile: String
    ) -> OfficialRateLimitSnapshot? {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let payload = dictionary["payload"] as? [String: Any],
              let rateLimits = payload["rate_limits"] as? [String: Any] else {
            return nil
        }

        let timestamp = stringValue(dictionary["timestamp"]).flatMap(parseTimestamp) ?? Date.distantPast

        return OfficialRateLimitSnapshot(
            limitID: stringValue(rateLimits["limit_id"]),
            limitName: stringValue(rateLimits["limit_name"]),
            primary: parseWindow(rateLimits["primary"]),
            secondary: parseWindow(rateLimits["secondary"]),
            displayWindow: displayWindow,
            observedAt: timestamp,
            sourceFile: sourceFile
        )
    }

    private static func parseWindow(_ value: Any?) -> RateLimitWindowSnapshot? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = doubleValue(dictionary["used_percent"]) else {
            return nil
        }

        return RateLimitWindowSnapshot(
            usedPercent: usedPercent,
            windowMinutes: integerValue(dictionary["window_minutes"]),
            resetsAt: integerValue(dictionary["resets_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func jsonlFiles(under root: URL, modifiedSince: Date) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "jsonl" else {
                continue
            }

            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            if let modified = values?.contentModificationDate, modified >= modifiedSince {
                files.append(file)
            }
        }

        return files.sorted {
            modificationDate($0) > modificationDate($1)
        }
    }

    private static func modificationDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            double
        case let int as Int:
            Double(int)
        case let string as String:
            Double(string)
        default:
            nil
        }
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            int
        case let double as Double:
            Int(double)
        case let string as String:
            Int(string)
        default:
            nil
        }
    }
}
