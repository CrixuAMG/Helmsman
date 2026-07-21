//
//  HelmsmanTests.swift
//  HelmsmanTests
//
//  Created by Christian Job Kaal on 16/07/2026.
//

import Testing
@testable import Helmsman

struct HelmsmanTests {

    @Test func testSupervisorLocalProvider() async throws {
        let provider = SupervisorLocalProvider(
            supervisorctlPath: "/opt/homebrew/bin/supervisorctl",
            supervisorConfigPath: "/Users/christianjobkaal/Code/supervisor-test/supervisord.conf",
            timeout: 10.0
        )
        
        let processes = try await provider.getAllProcesses()
        
        #expect(processes.count == 3, "Expected 3 processes")
        #expect(processes.contains { $0.name == "counter" }, "Expected counter process")
        #expect(processes.contains { $0.name == "ticker" }, "Expected ticker process")
        #expect(processes.contains { $0.name == "worker" }, "Expected worker process")
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

}
