import Foundation

final class SupervisorDockerProvider: ServiceManagerProvider, @unchecked Sendable {
    nonisolated static let defaultDockerEndpoint = "http://127.0.0.1:2375"

    private let container: String
    private let supervisorctlPath: String
    private let timeout: TimeInterval
    private let supervisorConfigPath: String?
    private let supervisorEndpoint: String?
    private let username: String?
    private let password: String?
    private let dockerBaseURL: URL?
    private let xmlrpcProvider: SupervisorXMLRPCProvider?

    init(
        container: String,
        supervisorctlPath: String,
        supervisorConfigPath: String?,
        supervisorEndpoint: String?,
        username: String?,
        password: String?,
        timeout: TimeInterval,
        dockerEndpoint: String?
    ) throws {
        self.container = container
        self.supervisorctlPath = supervisorctlPath
        self.supervisorConfigPath = Self.optionalText(supervisorConfigPath)
        self.supervisorEndpoint = Self.optionalText(supervisorEndpoint)
        self.username = Self.optionalText(username)
        self.password = Self.optionalText(password)
        self.timeout = timeout

        if let supervisorEndpoint = Self.optionalText(supervisorEndpoint) {
            guard let endpoint = URL(string: supervisorEndpoint) else {
                throw ConnectionError.invalidConfiguration("Valid Supervisor URL is required")
            }

            self.xmlrpcProvider = SupervisorXMLRPCProvider(
                endpoint: endpoint,
                username: Self.optionalText(username),
                password: Self.optionalText(password),
                timeout: timeout
            )
            self.dockerBaseURL = nil
            return
        }

        let endpoint = Self.normalizedDockerEndpoint(dockerEndpoint)
        guard let dockerBaseURL = URL(string: endpoint),
              let scheme = dockerBaseURL.scheme,
              ["http", "https"].contains(scheme) else {
            throw ConnectionError.invalidConfiguration("Valid Docker Engine URL is required. Use http:// or https://.")
        }

        self.xmlrpcProvider = nil
        self.dockerBaseURL = dockerBaseURL
    }

    private nonisolated static func optionalText(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private nonisolated static func normalizedDockerEndpoint(_ dockerEndpoint: String?) -> String {
        guard let dockerEndpoint = optionalText(dockerEndpoint) else {
            return defaultDockerEndpoint
        }

        if dockerEndpoint.hasPrefix("tcp://") {
            return "http://" + dockerEndpoint.dropFirst("tcp://".count)
        }

        return dockerEndpoint
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        if let xmlrpcProvider {
            return try await xmlrpcProvider.getAllProcesses()
        }

        let output = try await execInContainer(supervisorctlArguments("status"), allowsNonZeroExit: true)
        return SupervisorSSHProvider.parseStatusOutput(output)
    }

    nonisolated func startProcess(_ name: String) async throws {
        if let xmlrpcProvider {
            try await xmlrpcProvider.startProcess(name)
            return
        }

        let output = try await execInContainer(supervisorctlArguments("start", name))
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func stopProcess(_ name: String) async throws {
        if let xmlrpcProvider {
            try await xmlrpcProvider.stopProcess(name)
            return
        }

        let output = try await execInContainer(supervisorctlArguments("stop", name))
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func restartProcess(_ name: String) async throws {
        if let xmlrpcProvider {
            try await xmlrpcProvider.restartProcess(name)
            return
        }

        let output = try await execInContainer(supervisorctlArguments("restart", name))
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        guard xmlrpcProvider == nil else {
            return ProcessMetrics(timestamp: Date(), cpuPercent: 0, memoryMB: 0)
        }

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

    nonisolated func readProcessLog(_ name: String, stderr: Bool, offset: Int, maxBytes: Int) async throws -> ProcessLogChunk {
        if let xmlrpcProvider {
            return try await xmlrpcProvider.readProcessLog(name, stderr: stderr, offset: offset, maxBytes: maxBytes)
        }

        let variants: [[String]]
        if stderr {
            variants = [
                supervisorctlArguments("tail", "-\(maxBytes)", name, "stderr"),
                supervisorctlArguments("tail", "--stderr", name),
                supervisorctlArguments("tail", name, "stderr"),
            ]
        } else {
            variants = [
                supervisorctlArguments("tail", "-\(maxBytes)", name),
                supervisorctlArguments("tail", name),
            ]
        }

        var lastError: Error?
        for variant in variants {
            do {
                let output = try await execInContainer(variant)
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("Error") || trimmed.hasPrefix("ERROR") || trimmed.hasPrefix("error:") {
                    lastError = ProviderError.commandFailed(output)
                    continue
                }
                return ProcessLogChunk(content: output, nextOffset: -1)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ProviderError.commandFailed("Unable to tail log for '\(name)'")
    }

    nonisolated func clearProcessLogs(_ name: String) async throws {
        if let xmlrpcProvider {
            try await xmlrpcProvider.clearProcessLogs(name)
            return
        }

        let output = try await execInContainer(supervisorctlArguments("clear", name))
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    private nonisolated func supervisorctlArguments(_ arguments: String...) -> [String] {
        var command = [supervisorctlPath]

        if let supervisorConfigPath {
            command += ["-c", supervisorConfigPath]
        }

        if let supervisorEndpoint {
            command += ["-s", supervisorEndpoint]
        }

        if let username {
            command += ["-u", username]
        }

        if let password {
            command += ["-p", password]
        }

        command += arguments
        return command
    }

    private nonisolated func execInContainer(_ command: [String], allowsNonZeroExit: Bool = false) async throws -> String {
        guard let dockerBaseURL else {
            throw ConnectionError.invalidConfiguration("Docker Engine URL is required for Docker exec")
        }

        let execBody: [String: Any] = [
            "Cmd": command,
            "AttachStdout": true,
            "AttachStderr": true,
            "Tty": false
        ]

        let createURL = dockerBaseURL
            .appendingPathComponent("containers")
            .appendingPathComponent(container)
            .appendingPathComponent("exec")
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: execBody)
        createRequest.timeoutInterval = timeout

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let httpResponse = createResponse as? HTTPURLResponse else {
            throw ConnectionError.invalidConfiguration("Docker exec creation returned an invalid response")
        }

        guard httpResponse.statusCode == 201 else {
            throw ConnectionError.invalidConfiguration(
                "Docker exec creation failed for container '\(container)': HTTP \(httpResponse.statusCode) \(responseText(createData))"
            )
        }

        struct ExecCreateResponse: Decodable {
            let Id: String
        }
        let execInfo = try JSONDecoder().decode(ExecCreateResponse.self, from: createData)
        let execID = execInfo.Id

        let startURL = dockerBaseURL
            .appendingPathComponent("exec")
            .appendingPathComponent(execID)
            .appendingPathComponent("start")
        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: ["Detach": false, "Tty": false])
        startRequest.timeoutInterval = timeout

        let (startData, startResponse) = try await URLSession.shared.data(for: startRequest)
        guard let startHTTPResponse = startResponse as? HTTPURLResponse else {
            throw ConnectionError.invalidConfiguration("Docker exec start returned an invalid response")
        }

        guard startHTTPResponse.statusCode == 200 else {
            throw ConnectionError.invalidConfiguration(
                "Docker exec start failed for container '\(container)': HTTP \(startHTTPResponse.statusCode) \(responseText(startData))"
            )
        }

        let output = stripDockerExecFrames(startData)
        let exitCode = try await inspectExitCode(execID, dockerBaseURL: dockerBaseURL)
        guard exitCode == 0 || allowsNonZeroExit else {
            throw ProviderError.commandFailed(
                output.isEmpty ? "Docker command exited with status \(exitCode)" : output
            )
        }

        return output
    }

    private nonisolated func inspectExitCode(_ execID: String, dockerBaseURL: URL) async throws -> Int {
        let inspectURL = dockerBaseURL
            .appendingPathComponent("exec")
            .appendingPathComponent(execID)
            .appendingPathComponent("json")
        var inspectRequest = URLRequest(url: inspectURL)
        inspectRequest.httpMethod = "GET"
        inspectRequest.timeoutInterval = timeout

        let (inspectData, inspectResponse) = try await URLSession.shared.data(for: inspectRequest)
        guard let inspectHTTPResponse = inspectResponse as? HTTPURLResponse else {
            throw ConnectionError.invalidConfiguration("Docker exec inspect returned an invalid response")
        }

        guard inspectHTTPResponse.statusCode == 200 else {
            throw ConnectionError.invalidConfiguration(
                "Docker exec inspect failed: HTTP \(inspectHTTPResponse.statusCode) \(responseText(inspectData))"
            )
        }

        struct ExecInspectResponse: Decodable {
            let ExitCode: Int?
        }

        let inspectInfo = try JSONDecoder().decode(ExecInspectResponse.self, from: inspectData)
        return inspectInfo.ExitCode ?? 0
    }

    private nonisolated func responseText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        if output.isEmpty {
            return String(data: data, encoding: .utf8) ?? ""
        }

        return String(data: output, encoding: .utf8) ?? ""
    }
}
