import Foundation
import Testing
@testable import XRayDesignCore

private func events(_ bytes: some Sequence<UInt8>, limit: Int = 90_000_000) throws -> [Data] {
    var parser = MCPEventStream(limit: limit)
    var result: [Data] = []
    for byte in bytes {
        if let event = try parser.append(byte) { result.append(event) }
    }
    return result
}

@Test(arguments: ["\n", "\r\n", "\r"])
func parsesDesktopEventWithBlankLineTerminator(_ newline: String) throws {
    let json = #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}"#
    let wire = "event: message\(newline)data: \(json)\(newline)\(newline)"
    let result = try events(wire.utf8)
    #expect(result == [Data(json.utf8)])
    let envelope = try MCPEnvelope.result(from: #require(result.first), id: 1)
    #expect(envelope?["protocolVersion"] as? String == "2025-06-18")
}

@Test func preservesSSEDataWhitespaceAndMultilinePayload() throws {
    let wire = "\u{FEFF}: heartbeat\r\nid: 7\r\nevent: message\r\ndata: first\r\ndata:  second \r\n\r\n"
    #expect(try events(wire.utf8) == [Data("first\n second ".utf8)])
    #expect(try events("data\n\n".utf8) == [Data()])
}

@Test func handlesNotificationsBeforeTheMatchingResponse() throws {
    let wire = """
    : heartbeat

    data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed"}

    data: {"jsonrpc":"2.0","id":2,
    data: "result":{"tools":[]}}


    """
    let decoded = try events(wire.utf8)
    #expect(decoded.count == 2)
    #expect(try MCPEnvelope.result(from: #require(decoded.first), id: 2) == nil)
    let response = try MCPEnvelope.result(from: #require(decoded.last), id: 2)
    #expect((response?["tools"] as? [Any])?.isEmpty == true)
}

@Test func doesNotDispatchIncompleteEventsAtEOF() throws {
    #expect(try events("data: pending".utf8).isEmpty)
    #expect(try events("data: pending\n".utf8).isEmpty)
    #expect(try events(": heartbeat\n\n".utf8).isEmpty)
}

@Test func countsAllWireBytesBeforeBufferingThem() throws {
    var parser = MCPEventStream(limit: 5)
    for byte in "data:".utf8 { #expect(try parser.append(byte) == nil) }
    #expect(throws: DesignError.self) { try parser.append(0x20) }
    #expect(throws: DesignError.self) { try events("\n\n\n".utf8, limit: 2) }
}
