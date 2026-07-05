import Foundation

enum SQLiteCommandResult {
    case success(String)
    case failure(String)
}

enum SQLiteCommand {
    static func run(path: String, query: String, separator: String = "\t") -> SQLiteCommandResult {
        let executable = "/usr/bin/sqlite3"
        guard FileManager.default.fileExists(atPath: executable) else {
            return .failure("sqlite3 was not found at \(executable).")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-readonly", "-separator", separator, path, query]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return .failure(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return .success(output)
    }
}
