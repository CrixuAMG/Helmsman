import Foundation

final class SupervisorDockerProvider: ServiceManagerProvider, @unchecked Sendable {
    private let container: String
    private let supervisorctlPath: String
    private let timeout: TimeInterval
    private let dockerBaseURL: URL

    init(
        container: String,
        supervisorctlPath: String,
        timeout: TimeInterval,
        dockerEndpoint: String = "http://127.0.0.1:2375"
    ) {
        self.container = container
        self.supervisorctlPath = supervisorctlPath
        self.timeout = timeout
        self.dockerBaseURL = URL(string: dockerEndpoint) ?? URL(string: "http://127.0.0.1:2375")!
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        let output = try await execInContainer([supervisorctlPath, "status"])
        return SupervisorSSHProvider.parseStatusOutput(output)
    }

    nonisolated func startProcess(_ name: String) async throws {
        let output = try await execInContainer([supervisorctlPath, "start", name])
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func stopProcess(_ name: String) async throws {
        let output = try await execInContainer([supervisorctlPath, "stop", name])
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func restartProcess(_ name: String) async throws {
        let output = try await execInContainer([supervisorctlPath, "restart", name])
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        let psOutput = try await execInContainer(["ps", "-p", "\(pid)", "-o", "pcpu=,rss="])
        let trimmed = psOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let cpu = Double(parts[0]),
              let rssKB = Double(parts[1]) else {
            throw ProviderError.commandFailed("Could not parse metrics: \(psOutput)")
        }
        return ProcessMetrics(timestamp: Date(), cpuPercent: cpu, memoryMB: rssKB / 1024.0)
    }

    private nonisolated func execInContainer(_ command: [String]) async throws -> String {
        let escapedCmd = command.map { arg in
            arg.contains(" ") ? "'\(arg)'" : arg
        }.joined(separator: " ")

        let execBody: [String: Any] = [
            "Cmd": ["/bin/sh", "-c", escapedCmd],
            "AttachStdout": true,
            "AttachStderr": true
        ]

        let createURL = dockerBaseURL.appendingPathComponent("/containers/\(container)/exec")
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: execBody)
        createRequest.timeoutInterval = timeout

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let httpResponse = createResponse as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            let statusCode = (createResponse as? HTTPURLResponse)?.statusCode ?? 0
            let message = String(data: createData, encoding: .utf8) ?? ""
            throw ConnectionError.invalidConfiguration("Docker exec creation failed (HTTP \(statusCode)): \(message)")
        }

        struct ExecCreateResponse: Decodable {
            let Id: String
        }
        let execInfo = try JSONDecoder().decode(ExecCreateResponse.self, from: createData)
        let execID = execInfo.Id

        let startURL = dockerBaseURL.appendingPathComponent("/exec/\(execID)/start")
        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: ["Detach": false, "Tty": false])
        startRequest.timeoutInterval = timeout

        let (startData, startResponse) = try await URLSession.shared.data(for: startRequest)
        guard let startHTTPResponse = startResponse as? HTTPURLResponse,
              startHTTPResponse.statusCode == 200 else {
            let statusCode = (startResponse as? HTTPURLResponse)?.statusCode ?? 0
            let message = String(data: startData, encoding: .utf8) ?? ""
            throw ConnectionError.invalidConfiguration("Docker exec start failed (HTTP \(statusCode)): \(message)")
        }

        return stripDockerExecFrames(startData)
    }

    private nonisolated func stripDockerExecFrames(_ data: Data) -> String {
        var offset = 0
        var output = Data()
        while offset + 8 <= data.count {
            let frameSize = (UInt32(data[offset + 4]) << 24) |
                (UInt32(data[offset + 5]) << 16) |
                (UInt32(data[offset + 6]) << 8) |
                UInt32(data[offset + 7])
            offset += 8
            if frameSize > 0, offset + Int(frameSize) <= data.count {
                output.append(data[offset..<offset + Int(frameSize)])
                offset += Int(frameSize)
            } else {
                break
            }
        }
        return String(data: output, encoding: .utf8) ?? ""
    }
}
