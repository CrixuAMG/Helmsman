//
//  HelmsmanTests.swift
//  HelmsmanTests
//
//  Created by Christian Job Kaal on 16/07/2026.
//

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
}
