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
    private var settingsWindow: NSWindow?

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

    func selectRateLimitWindow(_ window: RateLimitWindow) {
        config.rateLimitDisplayWindow = window
        saveConfig()
        refresh()
    }

    func selectLanguage(_ language: AppLanguage) {
        config.language = language
        saveConfig()
        settingsWindow?.title = AppStrings(language: language).settings
        refresh()
    }

    func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let text = AppStrings(language: config.language)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = text.settings
        window.contentView = NSHostingView(rootView: SettingsView(viewModel: self))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func closeSettings() {
        settingsWindow?.close()
    }

    func openConfigFile() {
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

    private func saveConfig() {
        try? ConfigStore.save(config, to: configURL)
    }
}

private struct MenuContent: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let text = AppStrings(language: viewModel.config.language)

        VStack(alignment: .leading) {
            Text("\(Self.percentText(viewModel.snapshot.displayRemainingPercent)) \(text.remaining)")
                .font(.headline)
            if let rateLimit = viewModel.snapshot.officialRateLimit {
                Text(rateLimit.limitName ?? "Codex")
                    .foregroundStyle(.secondary)
                Text("\(text.menuBarShows): \(Self.displayWindowText(viewModel.config.rateLimitDisplayWindow, rateLimit: rateLimit, text: text))")
                    .foregroundStyle(.secondary)
                Text("\(Self.windowLabel(rateLimit.primary, fallback: text.fiveHourWindow, text: text)): \(Self.percentText(rateLimit.primary?.remainingPercent)) \(text.remaining)")
                Text("\(Self.windowLabel(rateLimit.secondary, fallback: text.sevenDayWindow, text: text)): \(Self.percentText(rateLimit.secondary?.remainingPercent)) \(text.remaining)")
                Text(Self.resetText(rateLimit, text: text))
                    .foregroundStyle(.secondary)
            } else {
                Text(text.liveLimitNotFound)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.snapshot.compactSummary())")
                Text("\(text.window): \(viewModel.snapshot.period.label)")
            }
            Text("\(text.source): \(viewModel.snapshot.source)")
                .foregroundStyle(.secondary)
            Text("\(text.updated): \(viewModel.snapshot.updatedAt.formatted(date: .omitted, time: .standard))")
                .foregroundStyle(.secondary)

            if !viewModel.snapshot.warnings.isEmpty {
                Divider()
                ForEach(viewModel.snapshot.warnings.prefix(4), id: \.self) { warning in
                    Text(warning)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            Menu {
                displayWindowButton(.primary, title: text.fiveHourRemaining)
                displayWindowButton(.secondary, title: text.sevenDayRemaining)
                displayWindowButton(.mostConstrained, title: text.lowerOfBoth)
            } label: {
                Label(text.menuBarShows, systemImage: "gauge")
            }
            Button {
                viewModel.refresh()
            } label: {
                Label(text.refreshNow, systemImage: "arrow.clockwise")
            }
            Button {
                viewModel.openSettings()
            } label: {
                Label(text.settings, systemImage: "gearshape")
            }
            Button {
                viewModel.openCodexSettings()
            } label: {
                Label(text.openCodex, systemImage: "terminal")
            }
            Divider()
            Button {
                viewModel.quit()
            } label: {
                Label(text.quit, systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private func displayWindowButton(_ window: RateLimitWindow, title: String) -> some View {
        Button {
            viewModel.selectRateLimitWindow(window)
        } label: {
            Label(
                title,
                systemImage: viewModel.config.rateLimitDisplayWindow == window ? "checkmark.circle.fill" : "circle"
            )
        }
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value else {
            return "--%"
        }
        return "\(Int(value.rounded()))%"
    }

    private static func displayWindowText(_ window: RateLimitWindow, rateLimit: OfficialRateLimitSnapshot, text: AppStrings) -> String {
        switch window {
        case .primary:
            return windowLabel(rateLimit.primary, fallback: text.fiveHourWindow, text: text)
        case .secondary:
            return windowLabel(rateLimit.secondary, fallback: text.sevenDayWindow, text: text)
        case .mostConstrained:
            return text.lowerOfBoth
        }
    }

    private static func windowLabel(_ snapshot: RateLimitWindowSnapshot?, fallback: String, text: AppStrings) -> String {
        guard let minutes = snapshot?.windowMinutes else {
            return fallback
        }

        if minutes % (24 * 60) == 0 {
            return text.dayWindow(minutes / (24 * 60))
        }
        if minutes % 60 == 0 {
            return text.hourWindow(minutes / 60)
        }
        return text.minuteWindow(minutes)
    }

    private static func resetText(_ rateLimit: OfficialRateLimitSnapshot, text: AppStrings) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = text.locale

        let primaryReset = rateLimit.primary?.resetsAt.map {
            "\(windowLabel(rateLimit.primary, fallback: text.fiveHourWindow, text: text)) \(text.resets) \(formatter.localizedString(for: $0, relativeTo: Date()))"
        }
        let secondaryReset = rateLimit.secondary?.resetsAt.map {
            "\(windowLabel(rateLimit.secondary, fallback: text.sevenDayWindow, text: text)) \(text.resets) \(formatter.localizedString(for: $0, relativeTo: Date()))"
        }

        return [primaryReset, secondaryReset]
            .compactMap { $0 }
            .joined(separator: " | ")
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let text = AppStrings(language: viewModel.config.language)

        VStack(alignment: .leading, spacing: 16) {
            Text(text.settings)
                .font(.headline)

            Picker(text.language, selection: Binding(
                get: { viewModel.config.language },
                set: { viewModel.selectLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(AppStrings.languageName(language)).tag(language)
                }
            }
            .pickerStyle(.segmented)

            Picker(text.menuBarShows, selection: Binding(
                get: { viewModel.config.rateLimitDisplayWindow },
                set: { viewModel.selectRateLimitWindow($0) }
            )) {
                Text(text.fiveHourRemaining).tag(RateLimitWindow.primary)
                Text(text.sevenDayRemaining).tag(RateLimitWindow.secondary)
                Text(text.lowerOfBoth).tag(RateLimitWindow.mostConstrained)
            }

            Divider()

            HStack {
                Button {
                    viewModel.openConfigFile()
                } label: {
                    Label(text.openSettingsFile, systemImage: "doc")
                }

                Spacer()

                Button(text.done) {
                    viewModel.closeSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct AppStrings {
    var appLanguage: AppLanguage

    init(language: AppLanguage) {
        self.appLanguage = language
    }

    var locale: Locale {
        switch appLanguage {
        case .english:
            Locale(identifier: "en_US")
        case .simplifiedChinese:
            Locale(identifier: "zh_Hans_CN")
        }
    }

    var remaining: String { appLanguage == .english ? "remaining" : "剩余" }
    var settings: String { appLanguage == .english ? "Settings" : "设置" }
    var language: String { appLanguage == .english ? "Language" : "语言" }
    var menuBarShows: String { appLanguage == .english ? "Menu Bar Shows" : "菜单栏显示" }
    var refreshNow: String { appLanguage == .english ? "Refresh Now" : "立即刷新" }
    var openSettingsFile: String { appLanguage == .english ? "Open Settings File" : "打开设置文件" }
    var openCodex: String { appLanguage == .english ? "Open Codex" : "打开 Codex" }
    var quit: String { appLanguage == .english ? "Quit" : "退出" }
    var done: String { appLanguage == .english ? "Done" : "完成" }
    var source: String { appLanguage == .english ? "Source" : "来源" }
    var updated: String { appLanguage == .english ? "Updated" : "更新" }
    var window: String { appLanguage == .english ? "Window" : "窗口" }
    var liveLimitNotFound: String { appLanguage == .english ? "Live Codex limit not found yet" : "还没有找到 Codex 实时额度" }
    var fiveHourRemaining: String { appLanguage == .english ? "5h remaining" : "5 小时剩余" }
    var sevenDayRemaining: String { appLanguage == .english ? "7d remaining" : "7 天剩余" }
    var lowerOfBoth: String { appLanguage == .english ? "Lower of 5h / 7d" : "5 小时 / 7 天中更低值" }
    var fiveHourWindow: String { appLanguage == .english ? "5h window" : "5 小时窗口" }
    var sevenDayWindow: String { appLanguage == .english ? "7d window" : "7 天窗口" }
    var resets: String { appLanguage == .english ? "resets" : "重置" }

    func hourWindow(_ value: Int) -> String {
        appLanguage == .english ? "\(value)h window" : "\(value) 小时窗口"
    }

    func dayWindow(_ value: Int) -> String {
        appLanguage == .english ? "\(value)d window" : "\(value) 天窗口"
    }

    func minuteWindow(_ value: Int) -> String {
        appLanguage == .english ? "\(value)m window" : "\(value) 分钟窗口"
    }

    static func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        }
    }
}
