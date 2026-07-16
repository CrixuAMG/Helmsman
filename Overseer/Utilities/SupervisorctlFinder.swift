import Foundation

enum SupervisorctlFinder {
    private static let knownPaths = [
        "/usr/bin/supervisorctl",
        "/usr/local/bin/supervisorctl",
        "/opt/homebrew/bin/supervisorctl",
        "/opt/local/bin/supervisorctl",
        "/usr/sbin/supervisorctl",
        "/opt/homebrew/sbin/supervisorctl",
    ]

    static func find() async -> String? {
        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return await findWithWhich()
    }

    private static func findWithWhich() async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["supervisorctl"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let path = result, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                    continuation.resume(returning: path)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
