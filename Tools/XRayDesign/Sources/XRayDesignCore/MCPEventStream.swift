import Foundation

/// Parses SSE bytes directly, preserving the empty lines that delimit events.
/// An event without its final blank line is intentionally not dispatched at EOF.
struct MCPEventStream {
    private let limit: Int
    private var count = 0
    private var line: [UInt8] = []
    private var data = Data()
    private var previousWasCR = false
    private var firstLine = true

    init(limit: Int = 90_000_000) { self.limit = limit }

    mutating func append(_ byte: UInt8) throws -> Data? {
        guard count < limit else {
            throw DesignError("Desktop MCP response exceeds the supported size limit.")
        }
        count += 1
        if previousWasCR {
            previousWasCR = false
            if byte == 0x0A { return nil }
        }
        if byte == 0x0D {
            previousWasCR = true
            return completeLine()
        }
        if byte == 0x0A { return completeLine() }
        line.append(byte)
        return nil
    }

    private mutating func completeLine() -> Data? {
        var completed = line
        line.removeAll(keepingCapacity: true)
        if firstLine {
            firstLine = false
            if completed.starts(with: [0xEF, 0xBB, 0xBF]) { completed.removeFirst(3) }
        }
        if completed.isEmpty {
            guard !data.isEmpty else { return nil }
            let event = Data(data.dropLast()) // SSE removes the last data-field newline.
            data.removeAll(keepingCapacity: true)
            return event
        }
        // Ignore comments and fields other than the exact, case-sensitive "data" field.
        let fieldEnd = completed.firstIndex(of: 0x3A) ?? completed.endIndex
        guard completed[..<fieldEnd].elementsEqual([0x64, 0x61, 0x74, 0x61]) else { return nil }
        var valueStart = fieldEnd
        if valueStart < completed.endIndex {
            valueStart += 1
            // SSE removes one optional ASCII space, not arbitrary whitespace.
            if valueStart < completed.endIndex, completed[valueStart] == 0x20 { valueStart += 1 }
        }
        data.append(contentsOf: completed[valueStart...])
        data.append(0x0A)
        return nil
    }
}
