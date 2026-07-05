import AppKit
import SwiftUI
import CodexUsageBarCore

private let launchOptions = LaunchOptions.parse()

@main
struct CodexUsageBarApp: App {
    @StateObject private var viewModel = UsageViewModel(options: launchOptions)

    init() {
        if launchOptions.once {
            let config = launchOptions.loadConfig(createIfMissing: false)
            let snapshot = UsageReader.snapshot(config: config)
            if launchOptions.json {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(snapshot),
                   let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            } else {
                print(snapshot.menuBarTitle())
                print(snapshot.compactSummary())
                print("Period: \(snapshot.period.label)")
                print("Source: \(snapshot.source)")
                if !snapshot.warnings.isEmpty {
                    print("Warnings:")
                    for warning in snapshot.warnings {
                        print("- \(warning)")
                    }
                }
            }
            Foundation.exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            Image(nsImage: viewModel.batteryImage)
                .renderingMode(.original)
                .accessibilityLabel("Codex remaining \(viewModel.title)")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var title = "--%"
    @Published var batteryImage = BatteryIconRenderer.image(percent: nil, health: .unknown)
    @Published var snapshot = UsageSnapshot(
        usedTokens: 0,
        tokenBudget: 0,
        threadCount: 0,
        period: .monthly,
        source: "loading"
    )
    @Published var config = UsageConfig()

    let configURL: URL
    private var timer: Timer?

    init(options: LaunchOptions) {
        self.configURL = options.configURL
        self.config = options.loadConfig(createIfMissing: true)
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: max(10, config.refreshIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        config = launchOptions.loadConfig(createIfMissing: true)
        snapshot = UsageReader.snapshot(config: config)
        title = snapshot.menuBarTitle()
        let health = snapshot.health(
            warningRemainingPercent: config.warningRemainingPercent,
            criticalRemainingPercent: config.criticalRemainingPercent
        )
        batteryImage = BatteryIconRenderer.image(percent: snapshot.displayRemainingPercent, health: health)
    }

    func openConfig() {
        NSWorkspace.shared.open(configURL)
    }

    func openCodexSettings() {
        if let url = URL(string: "codex://settings") {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

}

private struct MenuContent: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(Self.percentText(viewModel.snapshot.displayRemainingPercent) + " remaining")
                .font(.headline)
            if let rateLimit = viewModel.snapshot.officialRateLimit {
                Text(rateLimit.limitName ?? "Codex")
                    .foregroundStyle(.secondary)
                Text("\(Self.windowLabel(rateLimit.primary, fallback: "5h window")): \(Self.percentText(rateLimit.primary?.remainingPercent)) remaining")
                Text("\(Self.windowLabel(rateLimit.secondary, fallback: "7d window")): \(Self.percentText(rateLimit.secondary?.remainingPercent)) remaining")
                Text(Self.resetText(rateLimit))
                    .foregroundStyle(.secondary)
            } else {
                Text("Live Codex limit not found yet")
                    .foregroundStyle(.secondary)
                Text("\(viewModel.snapshot.compactSummary())")
                Text("Window: \(viewModel.snapshot.period.label)")
            }
            Text("Source: \(viewModel.snapshot.source)")
                .foregroundStyle(.secondary)
            Text("Updated: \(viewModel.snapshot.updatedAt.formatted(date: .omitted, time: .standard))")
                .foregroundStyle(.secondary)

            if !viewModel.snapshot.warnings.isEmpty {
                Divider()
                ForEach(viewModel.snapshot.warnings.prefix(4), id: \.self) { warning in
                    Text(warning)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            Button {
                viewModel.openConfig()
            } label: {
                Label("Open Settings File", systemImage: "gearshape")
            }
            Button {
                viewModel.openCodexSettings()
            } label: {
                Label("Open Codex", systemImage: "terminal")
            }
            Divider()
            Button {
                viewModel.quit()
            } label: {
                Label("Quit", systemImage: "xmark.circle")
            }
        }
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value else {
            return "--%"
        }
        return "\(Int(value.rounded()))%"
    }

    private static func windowLabel(_ snapshot: RateLimitWindowSnapshot?, fallback: String) -> String {
        guard let minutes = snapshot?.windowMinutes else {
            return fallback
        }

        if minutes % (24 * 60) == 0 {
            return "\(minutes / (24 * 60))d window"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60)h window"
        }
        return "\(minutes)m window"
    }

    private static func resetText(_ rateLimit: OfficialRateLimitSnapshot) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        let primaryReset = rateLimit.primary?.resetsAt.map {
            "\(windowLabel(rateLimit.primary, fallback: "5h window")) resets \(formatter.localizedString(for: $0, relativeTo: Date()))"
        }
        let secondaryReset = rateLimit.secondary?.resetsAt.map {
            "\(windowLabel(rateLimit.secondary, fallback: "7d window")) resets \(formatter.localizedString(for: $0, relativeTo: Date()))"
        }

        return [primaryReset, secondaryReset]
            .compactMap { $0 }
            .joined(separator: " | ")
    }
}
