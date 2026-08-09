import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

enum ProviderError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

final class SupervisorSSHProvider: ServiceManagerProvider, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let username: String
    private let authenticationMethod: AuthenticationMethod
    private let sshKeyPath: String?
    private let password: String?
    private let supervisorctlPath: String
    private let timeout: TimeInterval

    init(
        host: String,
        port: Int,
        username: String,
        authenticationMethod: AuthenticationMethod,
        sshKeyPath: String?,
        password: String?,
        supervisorctlPath: String,
        timeout: TimeInterval
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authenticationMethod = authenticationMethod
        self.sshKeyPath = sshKeyPath
        self.password = password
        self.supervisorctlPath = supervisorctlPath
        self.timeout = timeout
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        let output = try await executeSSH("\(supervisorctlPath) status", allowsNonZeroExit: true)
        return Self.parseStatusOutput(output)
    }

    nonisolated func startProcess(_ name: String) async throws {
        let output = try await executeSSH("\(supervisorctlPath) start \(name)")
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func stopProcess(_ name: String) async throws {
        let output = try await executeSSH("\(supervisorctlPath) stop \(name)")
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func restartProcess(_ name: String) async throws {
        let output = try await executeSSH("\(supervisorctlPath) restart \(name)")
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        let output = try await executeSSH("ps -p \(pid) -o %cpu=,rss=")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let cpu = Double(parts[0]),
              let rssKB = Double(parts[1]) else {
            throw ProviderError.commandFailed("Could not parse metrics: \(output)")
        }
        return ProcessMetrics(timestamp: Date(), cpuPercent: cpu, memoryMB: rssKB / 1024.0)
    }

    nonisolated func readProcessLog(_ name: String, stderr: Bool, offset: Int, maxBytes: Int) async throws -> ProcessLogChunk {
        let quoted = Self.quote(name)
        let variants: [String]
        if stderr {
            variants = [
                "\(supervisorctlPath) tail -\(maxBytes) \(quoted) stderr",
                "\(supervisorctlPath) tail --stderr \(quoted)",
                "\(supervisorctlPath) tail \(quoted) stderr",
            ]
        } else {
            variants = [
                "\(supervisorctlPath) tail -\(maxBytes) \(quoted)",
                "\(supervisorctlPath) tail \(quoted)",
            ]
        }

        var lastError: Error?
        for command in variants {
            do {
                let output = try await executeSSH(command)
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
        let output = try await executeSSH("\(supervisorctlPath) clear \(Self.quote(name))")
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    private nonisolated static func quote(_ value: String) -> String {
        value.contains(" ") ? "'\(value)'" : value
    }

    private nonisolated func executeSSH(_ command: String, allowsNonZeroExit: Bool = false) async throws -> String {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        do {
            let username = username
            let password = password
            let sshKeyPath = sshKeyPath

            let channel = try await ClientBootstrap(group: group)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
                .connectTimeout(.seconds(Int64(timeout)))
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let sync = channel.pipeline.syncOperations
                        let sshHandler = NIOSSHHandler(
                            role: .client(.init(
                                userAuthDelegate: UserAuthDelegate(
                                    username: username,
                                    password: password,
                                    keyPath: sshKeyPath
                                ),
                                serverAuthDelegate: AcceptAllHostKeysDelegate()
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )

                        try sync.addHandler(sshHandler)
                        try sync.addHandler(ErrorHandler())
                    }
                }
                .connect(host: host, port: port)
                .get()

            let exitStatusPromise = channel.eventLoop.makePromise(of: Int.self)
            let outputPromise = channel.eventLoop.makePromise(of: String.self)

            let childChannel: Channel = try await withCheckedThrowingContinuation { continuation in
                channel.eventLoop.execute {
                    do {
                        let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                        let promise = channel.eventLoop.makePromise(of: Channel.self)
                        promise.futureResult.whenComplete { result in
                            continuation.resume(with: result)
                        }
                        sshHandler.createChannel(promise) { childChannel, channelType in
                            guard channelType == .session else {
                                return channel.eventLoop.makeFailedFuture(SSHClientError.invalidChannelType)
                            }
                            return childChannel.pipeline.addHandlers([
                                ExecHandler(
                                    command: command,
                                    outputPromise: outputPromise,
                                    exitStatusPromise: exitStatusPromise
                                ),
                                ErrorHandler()
                            ])
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            try await childChannel.closeFuture.get()
            let exitStatus = try await exitStatusPromise.futureResult.get()

            try await channel.close().get()

            if exitStatus != 0 && !allowsNonZeroExit {
                let output = (try? await outputPromise.futureResult.get()) ?? ""
                throw ProviderError.commandFailed(output)
            }

            let output = try await outputPromise.futureResult.get()
            try await group.shutdownGracefully()
            return output
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }
}

// MARK: - Authentication Delegates

private nonisolated final class UserAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String?
    private let keyPath: String?

    init(username: String, password: String?, keyPath: String?) {
        self.username = username
        self.password = password
        self.keyPath = keyPath
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if availableMethods.contains(.password), let password = password {
            let offer = NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "ssh-connection",
                offer: .password(.init(password: password))
            )
            nextChallengePromise.succeed(offer)
        } else if availableMethods.contains(.publicKey), let keyPath = keyPath {
            guard let keyData = try? Data(contentsOf: URL(fileURLWithPath: keyPath)) else {
                nextChallengePromise.succeed(nil)
                return
            }
            do {
                let privateKey = try SSHKeyLoader.load(keyData: keyData)
                let offer = NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "ssh-connection",
                    offer: .privateKey(.init(privateKey: privateKey))
                )
                nextChallengePromise.succeed(offer)
            } catch {
                nextChallengePromise.succeed(nil)
            }
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

private nonisolated final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed()
    }
}

// MARK: - SSH Key Loader

private nonisolated enum SSHKeyLoader {

    enum KeyError: Error {
        case unsupportedFormat
        case unsupportedKeyType
        case parseFailed
    }

    static func load(keyData: Data) throws -> NIOSSHPrivateKey {
        guard let text = String(data: keyData, encoding: .utf8) else {
            throw KeyError.unsupportedFormat
        }
        if text.contains("-----BEGIN OPENSSH PRIVATE KEY-----") {
            return try loadOpenSSH(keyData: keyData)
        }
        if text.contains("-----BEGIN PRIVATE KEY-----")
            || text.contains("-----BEGIN EC PRIVATE KEY-----")
            || text.contains("-----BEGIN RSA PRIVATE KEY-----") {
            return try loadPEM(text: text)
        }
        throw KeyError.unsupportedFormat
    }

    // Parses OpenSSH private key format (ssh-keygen default).
    // Only ed25519 is supported; ECDSA/RSA keys should use PKCS#8 format.
    private static func loadOpenSSH(keyData: Data) throws -> NIOSSHPrivateKey {
        guard let text = String(data: keyData, encoding: .utf8) else {
            throw KeyError.parseFailed
        }
        let lines = text.components(separatedBy: .newlines)
        let b64 = lines.filter { !$0.hasPrefix("-----") }.joined()
        guard let decoded = Data(base64Encoded: b64) else {
            throw KeyError.parseFailed
        }
        var cursor = 0

        func readString() throws -> Data {
            guard cursor + 4 <= decoded.count else { throw KeyError.parseFailed }
            let len = Int(decoded.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: cursor, as: UInt32.self) }.bigEndian)
            cursor += 4
            guard cursor + len <= decoded.count else { throw KeyError.parseFailed }
            let value = decoded[cursor..<cursor + len]
            cursor += len
            return Data(value)
        }

        guard decoded[cursor..<cursor + 15].elementsEqual("openssh-key-v1\0".utf8) else {
            throw KeyError.parseFailed
        }
        cursor += 15
        let cipherName = String(data: try readString(), encoding: .utf8) ?? ""
        try _ = readString()
        try _ = readString()
        guard cursor + 4 <= decoded.count else { throw KeyError.parseFailed }
        let keyCount = Int(decoded.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: cursor, as: UInt32.self) }.bigEndian)
        cursor += 4
        guard keyCount >= 1 else { throw KeyError.parseFailed }
        try _ = readString()
        guard cipherName == "none" else { throw KeyError.unsupportedFormat }

        let privSection = try readString()
        var pc = 0

        func readPrivString() throws -> Data {
            guard pc + 4 <= privSection.count else { throw KeyError.parseFailed }
            let len = Int(privSection.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: pc, as: UInt32.self) }.bigEndian)
            pc += 4
            guard pc + len <= privSection.count else { throw KeyError.parseFailed }
            let value = privSection[pc..<pc + len]
            pc += len
            return Data(value)
        }

        pc += 8
        let keyType = String(data: try readPrivString(), encoding: .utf8) ?? ""

        switch keyType {
        case "ssh-ed25519":
            try _ = readPrivString()
            let privKeyData = try readPrivString()
            guard privKeyData.count >= 32 else { throw KeyError.parseFailed }
            let seed = privKeyData[0..<32]
            let curveKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return NIOSSHPrivateKey(ed25519Key: curveKey)
        default:
            throw KeyError.unsupportedKeyType
        }
    }

    private static func loadPEM(text: String) throws -> NIOSSHPrivateKey {
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: text) {
            return NIOSSHPrivateKey(p256Key: key)
        }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: text) {
            return NIOSSHPrivateKey(p384Key: key)
        }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: text) {
            return NIOSSHPrivateKey(p521Key: key)
        }
        let lines = text.components(separatedBy: .newlines)
        let b64 = lines.filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: b64) else { throw KeyError.parseFailed }
        if let key = try? P256.Signing.PrivateKey(derRepresentation: der) {
            return NIOSSHPrivateKey(p256Key: key)
        }
        if let key = try? P384.Signing.PrivateKey(derRepresentation: der) {
            return NIOSSHPrivateKey(p384Key: key)
        }
        if let key = try? P521.Signing.PrivateKey(derRepresentation: der) {
            return NIOSSHPrivateKey(p521Key: key)
        }
        throw KeyError.unsupportedKeyType
    }
}

// MARK: - Command Execution Handler

private nonisolated final class ExecHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let command: String
    private let outputPromise: EventLoopPromise<String>
    private let exitStatusPromise: EventLoopPromise<Int>
    private var outputBuffer: String = ""

    init(command: String, outputPromise: EventLoopPromise<String>, exitStatusPromise: EventLoopPromise<Int>) {
        self.command = command
        self.outputPromise = outputPromise
        self.exitStatusPromise = exitStatusPromise
    }

    func channelActive(context: ChannelHandlerContext) {
        let execRequest = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        context.triggerUserOutboundEvent(execRequest, promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }

        let text = String(buffer: buffer)
        if channelData.type == .stdErr {
            return
        }
        outputBuffer.append(text)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exitEvent as SSHChannelRequestEvent.ExitStatus:
            exitStatusPromise.succeed(exitEvent.exitStatus)
        case let exitEvent as SSHChannelRequestEvent.ExitSignal:
            exitStatusPromise.succeed(-1)
            outputBuffer.append("\n[\(exitEvent.signalName)]")
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        outputPromise.succeed(outputBuffer)
    }
}

// MARK: - Error Handler

private nonisolated final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - Errors

private nonisolated enum SSHClientError: Error {
    case invalidChannelType
    case commandExecFailed
}

// MARK: - Output Parsing

extension SupervisorSSHProvider {
    nonisolated static func parseStatusOutput(_ output: String) -> [SupervisorProcess] {
        output.split(separator: "\n").compactMap { line in
            parseProcessLine(String(line))
        }
    }

    private nonisolated static func parseProcessLine(_ line: String) -> SupervisorProcess? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let nameEnd = trimmed.firstIndex(where: { $0.isWhitespace }) else { return nil }
        let fullName = String(trimmed[trimmed.startIndex..<nameEnd])
        let rest = trimmed[nameEnd...].trimmingCharacters(in: .whitespaces)
        guard let statusEnd = rest.firstIndex(where: { $0.isWhitespace }) else {
            let status = mapStatus(String(rest))
            return splitName(fullName, status: status, description: String(rest))
        }
        let statusStr = String(rest[rest.startIndex..<statusEnd])
        let description = String(rest[statusEnd...]).trimmingCharacters(in: .whitespaces)
        let status = mapStatus(statusStr)
        return splitName(fullName, status: status, description: description)
    }

    private nonisolated static func splitName(_ fullName: String, status: ServiceStatus, description: String) -> SupervisorProcess {
        let parts = fullName.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return SupervisorProcess(
                name: String(parts[1]),
                group: String(parts[0]),
                status: status,
                description: description,
                pid: extractPid(from: description),
                uptime: extractUptime(from: description),
                exitStatus: nil
            )
        }
        return SupervisorProcess(
            name: fullName,
            group: fullName,
            status: status,
            description: description,
            pid: extractPid(from: description),
            uptime: extractUptime(from: description),
            exitStatus: nil
        )
    }

    private nonisolated static func mapStatus(_ raw: String) -> ServiceStatus {
        switch raw.uppercased() {
        case "RUNNING": .running
        case "STOPPED": .stopped
        case "STARTING": .starting
        case "BACKOFF": .backingoff
        case "STOPPING": .stopping
        case "EXITED": .exited
        case "FATAL": .fatal
        default: .unknown
        }
    }

    private nonisolated static func extractPid(from description: String) -> Int {
        guard let range = description.range(of: "pid (\\d+)", options: .regularExpression) else { return 0 }
        let match = description[range]
        guard let pidStart = match.firstIndex(of: " ") else { return 0 }
        let pidStr = String(match[match.index(after: pidStart)..<match.endIndex])
        return Int(pidStr) ?? 0
    }

    private nonisolated static func extractUptime(from description: String) -> TimeInterval? {
        guard let uptimeRange = description.range(of: "uptime ") else { return nil }
        let uptimeStr = String(description[uptimeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        var totalSeconds: TimeInterval = 0
        if let dayMatch = uptimeStr.range(of: "(\\d+)\\s+day", options: .regularExpression) {
            let dayStr = String(uptimeStr[dayMatch])
            if let days = dayStr.split(separator: " ").first.map({ Int($0) ?? 0 }) {
                totalSeconds += TimeInterval(days * 86400)
            }
        }
        if let timeRange = uptimeStr.range(of: "\\d+:\\d+:\\d+", options: .regularExpression) {
            let timeStr = String(uptimeStr[timeRange])
            let components = timeStr.split(separator: ":")
            if components.count == 3,
               let hours = Int(components[0]),
               let minutes = Int(components[1]),
               let seconds = Int(components[2]) {
                totalSeconds += TimeInterval(hours * 3600 + minutes * 60 + seconds)
            }
        }
        return totalSeconds > 0 ? totalSeconds : nil
    }
}
