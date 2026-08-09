import Foundation

final class XMLRPCResponseParser: NSObject, @unchecked Sendable, XMLParserDelegate {
    private let xml: String
    private let trimStrings: Bool
    nonisolated(unsafe) private var result: XMLRPCValue?
    nonisolated(unsafe) private var faultValue: XMLRPCValue?
    nonisolated(unsafe) private var error: Error?

    nonisolated(unsafe) private var elementStack: [String] = []
    nonisolated(unsafe) private var currentText = ""
    nonisolated(unsafe) private var pendingValue: XMLRPCValue?
    nonisolated(unsafe) private var containers: [XMLRPCContainer] = []
    nonisolated(unsafe) private var inFault = false

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

        if let faultValue {
            throw ServiceError.actionFailed("XML-RPC Fault: \(faultDescription(from: faultValue))")
        }

        guard let result = result else {
            throw ServiceError.actionFailed("No result in response")
        }

        return result
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "fault":
            inFault = true
        case "array":
            containers.append(.array([]))
        case "struct":
            containers.append(.struct(fields: [:], pendingName: nil))
        default:
            break
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let raw = currentText
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimStrings ? trimmed : raw

        switch elementName {
        case "name":
            setPendingStructName(trimmed)
        case "string":
            pendingValue = .string(value)
        case "int", "i4", "i8":
            if let intValue = Int(value) {
                pendingValue = .int(intValue)
            } else {
                error = ServiceError.actionFailed("Invalid integer value: \(value)")
            }
        case "boolean":
            pendingValue = .bool(value == "1" || value.lowercased() == "true")
        case "array":
            finishArray()
        case "struct":
            finishStruct()
        case "value":
            finishValue(defaultString: value)
        default:
            break
        }

        if elementStack.last == elementName {
            elementStack.removeLast()
        }
        currentText = ""
    }

    nonisolated func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = ServiceError.actionFailed("XML parse error: \(parseError.localizedDescription)")
    }

    private nonisolated func finishArray() {
        guard case .array(let items) = containers.popLast() else {
            error = ServiceError.actionFailed("Malformed XML-RPC array")
            return
        }
        pendingValue = .array(items)
    }

    private nonisolated func finishStruct() {
        guard case .struct(let fields, _) = containers.popLast() else {
            error = ServiceError.actionFailed("Malformed XML-RPC struct")
            return
        }
        pendingValue = .struct(fields)
    }

    private nonisolated func finishValue(defaultString: String) {
        guard let value = pendingValue ?? (defaultString.isEmpty ? nil : .string(defaultString)) else {
            return
        }

        if inFault, parentElement == "fault" {
            faultValue = value
        } else if parentElement == "param" {
            result = value
        } else {
            appendToCurrentContainer(value)
        }

        pendingValue = nil
    }

    private nonisolated func appendToCurrentContainer(_ value: XMLRPCValue) {
        guard let container = containers.popLast() else { return }

        switch container {
        case .array(var items):
            items.append(value)
            containers.append(.array(items))
        case .struct(var fields, let pendingName):
            guard let pendingName else {
                error = ServiceError.actionFailed("XML-RPC struct member is missing a name")
                containers.append(.struct(fields: fields, pendingName: pendingName))
                return
            }
            fields[pendingName] = value
            containers.append(.struct(fields: fields, pendingName: nil))
        }
    }

    private nonisolated func setPendingStructName(_ name: String) {
        guard let container = containers.popLast() else { return }

        switch container {
        case .array:
            containers.append(container)
        case .struct(let fields, _):
            containers.append(.struct(fields: fields, pendingName: name))
        }
    }

    private nonisolated var parentElement: String? {
        guard elementStack.count >= 2 else { return nil }
        return elementStack[elementStack.count - 2]
    }

    private nonisolated func faultDescription(from value: XMLRPCValue) -> String {
        guard case .struct(let fields) = value else {
            return "Unknown fault"
        }

        if case .string(let message) = fields["faultString"] {
            return message
        }

        if case .int(let code) = fields["faultCode"] {
            return "Fault code \(code)"
        }

        return "Unknown fault"
    }
}

private enum XMLRPCContainer: Sendable {
    case array([XMLRPCValue])
    case `struct`(fields: [String: XMLRPCValue], pendingName: String?)
}
