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
}
