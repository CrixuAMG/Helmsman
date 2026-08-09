import Foundation

struct ResolvedLogFile: Sendable {
    let serviceKey: String
    let url: URL
    let isStdout: Bool
}

struct ServiceLogDiskUsage: Identifiable, Sendable {
    let serviceName: String
    let stdoutBytes: Int64
    let stderrBytes: Int64

    var id: String { serviceName }
    var totalBytes: Int64 { stdoutBytes + stderrBytes }
}

enum LogDiskUsageProvider {

    /// Resolves the stdout/stderr log file locations from a supervisord.conf.
    /// Handles `%(here)s` expansion and maps grouped programs to `group:name` keys.
    static func parseConfig(_ configContent: String, configDirectory: URL) -> [ResolvedLogFile] {
        var files: [ResolvedLogFile] = []
        var currentProgram: String?
        var currentGroup: String?
        var groupForProgram: [String: String] = [:]
        var stdoutLogfile: String?
        var stderrLogfile: String?

        func flushProgram() {
            guard let program = currentProgram else { return }
            if let path = stdoutLogfile, path != "AUTO" {
                files.append(ResolvedLogFile(
                    serviceKey: serviceKey(for: program, groups: groupForProgram),
                    url: resolve(path, in: configDirectory),
                    isStdout: true
                ))
            }
            if let path = stderrLogfile, path != "AUTO" {
                files.append(ResolvedLogFile(
                    serviceKey: serviceKey(for: program, groups: groupForProgram),
                    url: resolve(path, in: configDirectory),
                    isStdout: false
                ))
            }
            currentProgram = nil
            stdoutLogfile = nil
            stderrLogfile = nil
        }

        for rawLine in configContent.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                flushProgram()
                let section = String(line.dropFirst().dropLast())
                if section.hasPrefix("program:") {
                    currentProgram = String(section.dropFirst("program:".count))
                    currentGroup = nil
                } else if section.hasPrefix("group:") {
                    currentGroup = String(section.dropFirst("group:".count))
                    currentProgram = nil
                } else {
                    currentProgram = nil
                    currentGroup = nil
                }
                continue
            }

            if let program = currentProgram {
                if let value = keyValue(line, key: "stdout_logfile") {
                    stdoutLogfile = value
                } else if let value = keyValue(line, key: "stderr_logfile") {
                    stderrLogfile = value
                }
                _ = program
            } else if let group = currentGroup,
                      let value = keyValue(line, key: "programs") {
                for member in value.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
                    groupForProgram[String(member)] = group
                }
            }
        }
        flushProgram()

        return files
    }

    /// Returns per-service log disk usage for a local connection.
    static func collect(for connection: Connection) -> [ServiceLogDiskUsage] {
        guard connection.connectionMethod == .local else { return [] }

        let files = resolvedFiles(for: connection)
        var totals: [String: ServiceLogDiskUsage] = [:]

        for file in files {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int64) ?? 0
            var usage = totals[file.serviceKey] ?? ServiceLogDiskUsage(
                serviceName: file.serviceKey,
                stdoutBytes: 0,
                stderrBytes: 0
            )
            if file.isStdout {
                usage = ServiceLogDiskUsage(
                    serviceName: file.serviceKey,
                    stdoutBytes: usage.stdoutBytes + size,
                    stderrBytes: usage.stderrBytes
                )
            } else {
                usage = ServiceLogDiskUsage(
                    serviceName: file.serviceKey,
                    stdoutBytes: usage.stdoutBytes,
                    stderrBytes: usage.stderrBytes + size
                )
            }
            totals[file.serviceKey] = usage
        }

        return totals.values.sorted { $0.serviceName < $1.serviceName }
    }

    static func totalBytes(for connection: Connection) -> Int64 {
        collect(for: connection).reduce(0) { $0 + $1.totalBytes }
    }

    /// Deletes resolved log files that haven't been modified within `retentionDays`.
    /// Returns the number of files removed and the bytes reclaimed.
    static func cleanupOldLogs(for connection: Connection, retentionDays: Int) -> (files: Int, bytes: Int64) {
        guard connection.connectionMethod == .local else { return (0, 0) }

        let files = resolvedFiles(for: connection)
        var removed = 0
        var bytes: Int64 = 0

        for file in files {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path)
            guard let attributes else { continue }
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            guard modified < Date().addingTimeInterval(TimeInterval(-retentionDays) * 86_400) else { continue }

            if (try? FileManager.default.removeItem(at: file.url)) != nil {
                removed += 1
                bytes += (attributes[.size] as? Int64) ?? 0
            }
        }

        return (removed, bytes)
    }

    // MARK: - Helpers

    private static func resolvedFiles(for connection: Connection) -> [ResolvedLogFile] {
        guard let configPath = connection.supervisorConfigPath,
              let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return []
        }
        let configDirectory = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        return parseConfig(content, configDirectory: configDirectory)
    }

    private static func serviceKey(for program: String, groups: [String: String]) -> String {
        if let group = groups[program] {
            return "\(group):\(program)"
        }
        return program
    }

    private static func resolve(_ path: String, in configDirectory: URL) -> URL {
        if path.hasPrefix("%(here)s") {
            let relative = String(path.dropFirst("%(here)s".count))
            return configDirectory.appendingPathComponent(relative)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return configDirectory.appendingPathComponent(path)
    }

    private static func keyValue(_ line: String, key: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let lhs = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard lhs == key else { return nil }
        return String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
    }
}
