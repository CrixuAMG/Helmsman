//
//  HelmsmanTests.swift
//  HelmsmanTests
//
//  Created by Christian Job Kaal on 16/07/2026.
//

import Foundation
import Testing
@testable import Helmsman

struct HelmsmanTests {
    @Test func testXMLRPCResponseParserHandlesArrayOfStructs() throws {
        let xml = """
        <?xml version='1.0'?>
        <methodResponse>
        <params>
        <param>
        <value><array><data>
        <value><struct>
        <member><name>name</name><value><string>web</string></value></member>
        <member><name>group</name><value><string>web</string></value></member>
        <member><name>statename</name><value><string>RUNNING</string></value></member>
        <member><name>pid</name><value><int>123</int></value></member>
        <member><name>description</name><value><string>pid 123, uptime 0:01:00</string></value></member>
        </struct></value>
        <value><struct>
        <member><name>name</name><value><string>00</string></value></member>
        <member><name>group</name><value><string>worker</string></value></member>
        <member><name>statename</name><value><string>STOPPED</string></value></member>
        <member><name>pid</name><value><int>0</int></value></member>
        <member><name>description</name><value><string>Not started</string></value></member>
        </struct></value>
        </data></array></value>
        </param>
        </params>
        </methodResponse>
        """

        let value = try XMLRPCResponseParser(xml: xml).parse()
        guard case .array(let items) = value else {
            Issue.record("Expected array response")
            return
        }

        #expect(items.count == 2)

        guard case .struct(let firstProcess) = items[0],
              case .string("web") = firstProcess["name"],
              case .string("RUNNING") = firstProcess["statename"],
              case .int(123) = firstProcess["pid"] else {
            Issue.record("Expected first process struct")
            return
        }

        guard case .struct(let secondProcess) = items[1],
              case .string("worker") = secondProcess["group"],
              case .string("STOPPED") = secondProcess["statename"],
              case .int(0) = secondProcess["pid"] else {
            Issue.record("Expected second process struct")
            return
        }
    }

    @Test func testParseStatusOutput() {
        let output = """
counter                          RUNNING   pid 72250, uptime 0:11:07
ticker                           RUNNING   pid 67285, uptime 0:31:08
worker                           RUNNING   pid 67286, uptime 0:31:08
"""

        let processes = SupervisorSSHProvider.parseStatusOutput(output)

        #expect(processes.count == 3, "Expected 3 processes")
        #expect(processes[0].name == "counter", "First process should be counter")
        #expect(processes[0].status == .running, "Counter should be running")
        #expect(processes[1].name == "ticker", "Second process should be ticker")
        #expect(processes[2].name == "worker", "Third process should be worker")
    }

    @Test func testParseStatusOutputWithGroup() {
        let output = """
nginx:nginx                        RUNNING   pid 100, uptime 0:11:07
nginx:php-fpm                      RUNNING   pid 101, uptime 0:11:07
api:worker-1                       FATAL     Exited too quickly
"""

        let processes = SupervisorSSHProvider.parseStatusOutput(output)

        #expect(processes.count == 3)
        #expect(processes[0].group == "nginx")
        #expect(processes[0].name == "nginx")
        #expect(processes[1].group == "nginx")
        #expect(processes[1].name == "php-fpm")
        #expect(processes[2].status == .fatal)
    }

    // MARK: - Rolling Tail Merge

    @Test func testRollingTailMergeAppendsDelta() async {
        let store = await ProcessLogStore()

        // First chunk seeds the buffer.
        await store.merge(ProcessLogChunk(content: "line 1\nline 2\nline 3\n", nextOffset: -1), for: "a", stream: .stdout)
        #expect(await store.content(for: "a", stream: .stdout) == "line 1\nline 2\nline 3\n")

        // A new rolling window that still contains the tail of the previous one
        // should only append the delta (overlap detection).
        await store.merge(ProcessLogChunk(content: "line 2\nline 3\nline 4\n", nextOffset: -1), for: "a", stream: .stdout)
        let merged = await store.content(for: "a", stream: .stdout)
        #expect(merged == "line 1\nline 2\nline 3\nline 4\n")
    }

    @Test func testRollingTailMergeWithoutOverlapReplaces() async {
        let store = await ProcessLogStore()

        await store.merge(ProcessLogChunk(content: "old content\n", nextOffset: -1), for: "a", stream: .stdout)
        await store.merge(ProcessLogChunk(content: "brand new\n", nextOffset: -1), for: "a", stream: .stdout)

        #expect(await store.content(for: "a", stream: .stdout) == "brand new\n")
    }

    @Test func testOffsetBasedMergeAppends() async {
        let store = await ProcessLogStore()

        await store.merge(ProcessLogChunk(content: "hello\n", nextOffset: 6), for: "a", stream: .stdout)
        await store.merge(ProcessLogChunk(content: "world\n", nextOffset: 12), for: "a", stream: .stdout)

        #expect(await store.content(for: "a", stream: .stdout) == "hello\nworld\n")
        #expect(await store.offset(for: "a", stream: .stdout) == 12)
    }

    // MARK: - Event Detection

    private func makeService(name: String, status: ServiceStatus, pid: Int, uptime: TimeInterval? = nil) -> Service {
        Service(
            name: name,
            group: name,
            status: status,
            description: "",
            pid: pid,
            uptime: uptime,
            exitStatus: nil
        )
    }

    @Test func testDetectRestartOnPIDChange() {
        let old = [makeService(name: "worker", status: .running, pid: 100, uptime: 500)]
        let new = [makeService(name: "worker", status: .running, pid: 200, uptime: 5)]

        let events = ProcessEventDetector.detectEvents(between: old, and: new)

        #expect(events.count == 1)
        #expect(events[0].kind == .restarted)
        #expect(events[0].serviceID == "worker:worker")
    }

    @Test func testDetectStopAndStartTransitions() {
        let old = [makeService(name: "worker", status: .running, pid: 100)]
        let stopped = [makeService(name: "worker", status: .stopped, pid: 0)]
        let started = [makeService(name: "worker", status: .running, pid: 100)]

        let stopEvents = ProcessEventDetector.detectEvents(between: old, and: stopped)
        let startEvents = ProcessEventDetector.detectEvents(between: stopped, and: started)

        #expect(stopEvents.count == 1)
        #expect(stopEvents[0].kind == .stopped)
        #expect(startEvents.count == 1)
        #expect(startEvents[0].kind == .started)
    }

    @Test func testDetectCrashedTransition() {
        let old = [makeService(name: "worker", status: .running, pid: 100)]
        let crashed = [makeService(name: "worker", status: .backingoff, pid: 0)]

        let events = ProcessEventDetector.detectEvents(between: old, and: crashed)

        #expect(events.count == 1)
        #expect(events[0].kind == .crashed)
    }

    @MainActor
    @Test func testEventStoreRestartNumberingAndRuntime() {
        let store = ProcessEventStore()

        store.record(.started, detail: "Process started", for: "worker:worker")
        store.record(.restarted, detail: "", for: "worker:worker")
        store.record(.restarted, detail: "", for: "worker:worker")

        #expect(store.restartCount(for: "worker:worker") == 2)

        let events = store.events(for: "worker:worker")
        #expect(events[1].detail.contains("Restart #1"))
        #expect(events[2].detail.contains("Restart #2"))

        store.record(.stopped, detail: "Process stopped", for: "worker:worker")
        store.record(.started, detail: "Process started", for: "worker:worker")
        #expect(store.averageRuntime(for: "worker:worker") != nil)
    }

    // MARK: - Log Disk Usage

    @Test func testParseConfigResolvesLogFiles() {
        let config = """
        [supervisord]
        logfile=%(here)s/supervisord.log

        [program:counter]
        command=bash %(here)s/counter.sh
        stdout_logfile=%(here)s/counter.log
        stderr_logfile=%(here)s/counter_err.log

        [program:worker]
        command=bash %(here)s/worker.sh
        stdout_logfile=/var/log/worker.log

        [group:api]
        programs=api,worker-1

        [program:api]
        command=bash %(here)s/api.sh
        stdout_logfile=%(here)s/api.log
        """

        let dir = URL(fileURLWithPath: "/tmp/helmsman-test-config")
        let files = LogDiskUsageProvider.parseConfig(config, configDirectory: dir)

        #expect(files.count == 4)
        #expect(files.contains(where: { $0.serviceKey == "counter" && $0.isStdout && $0.url.path.hasSuffix("counter.log") }))
        #expect(files.contains(where: { $0.serviceKey == "counter" && !$0.isStdout && $0.url.path.hasSuffix("counter_err.log") }))
        #expect(files.contains(where: { $0.serviceKey == "worker" && $0.url.path == "/var/log/worker.log" }))
        #expect(files.contains(where: { $0.serviceKey == "api:api" && $0.isStdout }))
    }

    @MainActor
    @Test func testCollectSizesLogFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("helmsman-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent("supervisord.conf")
        let logPath = dir.appendingPathComponent("counter.log")
        try "hello world".write(to: logPath, atomically: true, encoding: .utf8)
        try """
        [program:counter]
        command=bash %(here)s/counter.sh
        stdout_logfile=%(here)s/counter.log
        """.write(to: configPath, atomically: true, encoding: .utf8)

        let connection = Connection(
            name: "test",
            supervisorConfigPath: configPath.path,
            connectionMethod: .local
        )

        let usage = LogDiskUsageProvider.collect(for: connection)

        #expect(usage.count == 1)
        #expect(usage[0].serviceName == "counter")
        #expect(usage[0].stdoutBytes == 11)
    }

    @MainActor
    @Test func testCleanupRemovesOnlyOldLogs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("helmsman-cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent("supervisord.conf")
        let oldLog = dir.appendingPathComponent("old.log")
        let freshLog = dir.appendingPathComponent("fresh.log")
        try "old".write(to: oldLog, atomically: true, encoding: .utf8)
        try "fresh".write(to: freshLog, atomically: true, encoding: .utf8)
        try """
        [program:counter]
        command=bash %(here)s/counter.sh
        stdout_logfile=%(here)s/old.log
        stderr_logfile=%(here)s/fresh.log
        """.write(to: configPath, atomically: true, encoding: .utf8)

        let oldDate = Date().addingTimeInterval(-31 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldLog.path)

        let connection = Connection(
            name: "test",
            supervisorConfigPath: configPath.path,
            connectionMethod: .local
        )

        let result = LogDiskUsageProvider.cleanupOldLogs(for: connection, retentionDays: 30)

        #expect(result.files == 1)
        #expect(result.bytes == 3)
        #expect(!FileManager.default.fileExists(atPath: oldLog.path))
        #expect(FileManager.default.fileExists(atPath: freshLog.path))
    }
}
