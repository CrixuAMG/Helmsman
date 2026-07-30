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
        worker                           STOPPED   Not started
        """

        let processes = SupervisorSSHProvider.parseStatusOutput(output)

        #expect(processes.count == 3)
        #expect(processes[0].name == "counter")
        #expect(processes[0].status == .running)
        #expect(processes[1].name == "ticker")
        #expect(processes[2].name == "worker")
        #expect(processes[2].status == .stopped)
    }
}
