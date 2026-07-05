import Foundation
import CodexUsageBarCore

struct LaunchOptions {
    var once = false
    var json = false
    var configURL: URL = ConfigStore.defaultConfigURL
    var budgetOverride: Int?
    var periodOverride: BudgetPeriod?
    var codexHomeOverride: String?

    static func parse(arguments: [String] = CommandLine.arguments) -> LaunchOptions {
        var options = LaunchOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--once":
                options.once = true
            case "--json":
                options.json = true
            case "--config":
                if let value = value(after: &index, in: arguments) {
                    options.configURL = URL(fileURLWithPath: PathExpander.expand(value))
                }
            case "--budget":
                if let value = value(after: &index, in: arguments) {
                    options.budgetOverride = Int(value)
                }
            case "--period":
                if let value = value(after: &index, in: arguments) {
                    options.periodOverride = BudgetPeriod(rawValue: value)
                }
            case "--codex-home":
                if let value = value(after: &index, in: arguments) {
                    options.codexHomeOverride = value
                }
            case "--help", "-h":
                print(Self.help)
                Foundation.exit(0)
            default:
                break
            }
            index += 1
        }

        return options
    }

    func loadConfig(createIfMissing: Bool) -> UsageConfig {
        var config = (try? ConfigStore.load(from: configURL, createIfMissing: createIfMissing)) ?? UsageConfig()
        if let budgetOverride {
            config.tokenBudget = budgetOverride
        }
        if let periodOverride {
            config.period = periodOverride
        }
        if let codexHomeOverride {
            config.codexHome = codexHomeOverride
        }
        return config
    }

    private static func value(after index: inout Int, in arguments: [String]) -> String? {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            return nil
        }
        index = nextIndex
        return arguments[nextIndex]
    }

    static let help = """
    CodexUsageBar

    Options:
      --once              Print one usage snapshot and exit.
      --json              With --once, print JSON.
      --config PATH       Use a custom config file.
      --budget TOKENS     Override configured token budget.
      --period PERIOD     daily, weekly, monthly, or rolling24h.
      --codex-home PATH   Override Codex home directory.
    """
}
