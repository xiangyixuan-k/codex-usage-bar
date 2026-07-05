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
            Label(viewModel.title, systemImage: viewModel.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var title = "Codex --"
    @Published var symbolName = "gauge.with.dots.needle.bottom.50percent"
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
        symbolName = symbol(for: snapshot.health(
            warningRemainingPercent: config.warningRemainingPercent,
            criticalRemainingPercent: config.criticalRemainingPercent
        ))
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

    private func symbol(for health: UsageHealth) -> String {
        switch health {
        case .ok:
            "gauge.with.dots.needle.bottom.50percent"
        case .warning:
            "gauge.with.dots.needle.67percent"
        case .critical:
            "exclamationmark.triangle"
        case .unknown:
            "questionmark.circle"
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(viewModel.snapshot.compactSummary())
                .font(.headline)
            Text("Window: \(viewModel.snapshot.period.label)")
            Text("Threads/events: \(viewModel.snapshot.threadCount)")
            Text("Source: \(viewModel.snapshot.source)")
            Text("Updated: \(viewModel.snapshot.updatedAt.formatted(date: .omitted, time: .standard))")

            if !viewModel.snapshot.warnings.isEmpty {
                Divider()
                ForEach(viewModel.snapshot.warnings.prefix(4), id: \.self) { warning in
                    Text(warning)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            Button("Refresh") {
                viewModel.refresh()
            }
            Button("Open Config") {
                viewModel.openConfig()
            }
            Button("Open Codex Settings") {
                viewModel.openCodexSettings()
            }
            Divider()
            Button("Quit") {
                viewModel.quit()
            }
        }
    }
}
