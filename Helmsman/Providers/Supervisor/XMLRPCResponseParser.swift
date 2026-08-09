import Foundation

final class XMLRPCResponseParser: NSObject, @unchecked Sendable, XMLParserDelegate {
    private let xml: String
    private let trimStrings: Bool
    nonisolated(unsafe) private var result: XMLRPCValue?
    nonisolated(unsafe) private var error: Error?

    nonisolated(unsafe) private var currentElement: String = ""
    nonisolated(unsafe) private var currentText: String = ""
    nonisolated(unsafe) private var valueStack: [XMLRPCValue] = []
    nonisolated(unsafe) private var nameStack: [String] = []
    nonisolated(unsafe) private var structFields: [[String: XMLRPCValue]] = []
    nonisolated(unsafe) private var inFault = false
    nonisolated(unsafe) private var faultString: String = ""

    nonisolated init(xml: String, trimStrings: Bool = true) {
        self.xml = xml
        self.trimStrings = trimStrings
    }

    nonisolated func parse() throws -> XMLRPCValue {
        guard let data = xml.data(using: .utf8) else {
            throw ServiceError.actionFailed("Invalid XML encoding")
        }

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if let error = error {
            throw error
        }

        if inFault {
            throw ServiceError.actionFailed("XML-RPC Fault: \(faultString)")
        }

        guard let result = result else {
            throw ServiceError.actionFailed("No result in response")
        }

        return result
    }

    nonisolated func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "fault":
            inFault = true
        case "struct":
            structFields.append([:])
        case "array":
            valueStack.append(.array([]))
        default:
            break
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    nonisolated func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value: String
        if trimStrings {
            value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            value = currentText
        }

        switch elementName {
        case "name":
            nameStack.append(value)

        case "string":
            pushValue(.string(value))

        case "int", "i4", "i8":
            if let intVal = Int(value) {
                pushValue(.int(intVal))
            }

        case "boolean":
            pushValue(.bool(value == "1" || value.lowercased() == "true"))

        case "member":
            if let name = nameStack.popLast(),
               let value = valueStack.popLast(),
               !structFields.isEmpty {
                structFields[structFields.count - 1][name] = value
            }

        case "struct":
            if let fields = structFields.popLast() {
                pushValue(.struct(fields))
            }

        case "array":
            if case .array(let items) = valueStack.popLast() {
                pushValue(.array(items))
            }

        case "value":
            if !value.isEmpty && valueStack.isEmpty {
                pushValue(.string(value))
            }

        case "param":
            if let value = valueStack.popLast() {
                result = value
            }

        case "fault":
            if case .struct(let fields) = valueStack.popLast(),
               case .string(let message) = fields["faultString"] {
                faultString = message
            }

        default:
            break
        }

        currentText = ""
    }

    nonisolated func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = ServiceError.actionFailed("XML parse error: \(parseError.localizedDescription)")
    }

    private nonisolated func pushValue(_ value: XMLRPCValue) {
        if case .array(var items) = valueStack.last {
            valueStack.removeLast()
            items.append(value)
            valueStack.append(.array(items))
        } else {
            valueStack.append(value)
        }
    }
}
