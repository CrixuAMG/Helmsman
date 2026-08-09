import Foundation
import Observation

enum LogStream: String, CaseIterable, Identifiable, Sendable {
    case stdout
    case stderr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stdout: "Stdout"
        case .stderr: "Stderr"
        }
    }
}

@MainActor
@Observable
final class ProcessLogStore {
    private struct Entry {
        var content: String = ""
        var offset: Int = -1
        var lastFetchDate: Date?
        var lastError: String?
    }

    private var buffers: [String: [LogStream: Entry]] = [:]

    let maxBufferBytes = 250_000
    let maxFetchBytes = 8_192

    func merge(_ chunk: ProcessLogChunk, for serviceID: String, stream: LogStream) {
        var entry = buffers[serviceID, default: [:]][stream] ?? Entry()

        if chunk.nextOffset >= 0 {
            entry.content = String((entry.content + chunk.content).suffix(maxBufferBytes))
            entry.offset = chunk.nextOffset
        } else {
            entry.content = Self.appendRollingTail(chunk.content, to: entry.content, maxBytes: maxBufferBytes)
            entry.offset = -1
        }

        entry.lastFetchDate = Date()
        entry.lastError = nil
        buffers[serviceID, default: [:]][stream] = entry
    }

    func record(error: Error, for serviceID: String, stream: LogStream) {
        var entry = buffers[serviceID, default: [:]][stream] ?? Entry()
        entry.lastError = error.localizedDescription
        buffers[serviceID, default: [:]][stream] = entry
    }

    func content(for serviceID: String, stream: LogStream) -> String {
        buffers[serviceID]?[stream]?.content ?? ""
    }

    func offset(for serviceID: String, stream: LogStream) -> Int {
        buffers[serviceID]?[stream]?.offset ?? -1
    }

    func lastFetchDate(for serviceID: String, stream: LogStream) -> Date? {
        buffers[serviceID]?[stream]?.lastFetchDate
    }

    func lastError(for serviceID: String, stream: LogStream) -> String? {
        buffers[serviceID]?[stream]?.lastError
    }

    func clear(for serviceID: String) {
        buffers[serviceID] = nil
    }

    func clearAll() {
        buffers.removeAll()
    }

    /// Merges a rolling tail window into the existing buffer by finding the
    /// longest suffix of the current buffer that is a prefix of the new chunk,
    /// then appending only the delta. If no overlap exists the buffer is
    /// replaced (log was cleared or the window slid past the old content).
    private static func appendRollingTail(_ newChunk: String, to buffer: String, maxBytes: Int) -> String {
        guard !newChunk.isEmpty else { return buffer }
        guard !buffer.isEmpty else { return String(newChunk.suffix(maxBytes)) }
        guard newChunk != buffer else { return buffer }

        let maxOverlap = min(buffer.count, newChunk.count)

        if newChunk.hasPrefix(buffer) {
            let delta = newChunk.dropFirst(buffer.count)
            return String((buffer + delta).suffix(maxBytes))
        }

        if maxOverlap > 0 {
            for length in stride(from: maxOverlap, through: 1, by: -1) {
                if newChunk.hasPrefix(buffer.suffix(length)) {
                    let delta = newChunk.dropFirst(length)
                    return String((buffer + delta).suffix(maxBytes))
                }
            }
        }

        return String(newChunk.suffix(maxBytes))
    }
}
