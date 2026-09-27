import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import XRayDesignCore

private let sourceURL = "https://www.figma.com/design/ExampleFile/Example?node-id=12-34"

private func makePNG(red: CGFloat = 1) throws -> Data {
    let context = try #require(CGContext(data: nil, width: 2, height: 4, bitsPerComponent: 8,
                                       bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 4))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("xray-design-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

@Test func parsesFigmaLinksWithoutLosingBranchOrNodeIdentity() throws {
    let ordinary = try DesignSource(name: "example", figmaURL: sourceURL)
    #expect(ordinary.fileKey == "ExampleFile")
    #expect(ordinary.nodeID == "12:34")
    let branch = try DesignSource(name: "example", figmaURL: "https://figma.com/design/MainKey/branch/BranchKey/Example?node-id=12%3A34")
    #expect(branch.fileKey == "BranchKey")
    #expect(branch.nodeID == "12:34")
    for invalid in [
        "https://figma.com.evil.example/design/ExampleFile/Example?node-id=12-34",
        "https://figma.com@evil.example/design/ExampleFile/Example?node-id=12-34",
        "http://figma.com/design/ExampleFile/Example?node-id=12-34",
        sourceURL + "&node-id=99-99",
        "https://figma.com/design/ExampleFile/Example",
    ] {
        #expect(throws: DesignError.self) { try DesignSource(name: "example", figmaURL: invalid) }
    }
    for name in ["../outside", "init", "some-name", "1name", "line\nbreak"] {
        #expect(throws: DesignError.self) { try DesignSource(name: name, figmaURL: sourceURL) }
    }
}

@Test func requiresExactHumanFileConfirmation() throws {
    let source = try DesignSource(name: "example", figmaURL: sourceURL)
    #expect(throws: DesignError.self) { try source.confirm(openFile: nil) }
    #expect(throws: DesignError.self) { try source.confirm(openFile: "AnotherFile") }
    try source.confirm(openFile: "ExampleFile")
}

@Test func rejectsUnsafeOrAmbiguousMetadata() throws {
    let valid = "<frame id=\"12:34\" name=\"Example\" width=\"2\" height=\"4\"/>"
    #expect(try NodeGeometry.parse(xml: valid, expectedNodeID: "12:34").width == 2)
    for xml in [
        valid.replacingOccurrences(of: "12:34", with: "99:99"),
        valid.replacingOccurrences(of: "width=\"2\"", with: "width=\"0\""),
        valid.replacingOccurrences(of: "/>", with: " hidden=\"true\"/>"),
        "<!DOCTYPE frame SYSTEM \"file:///etc/passwd\">" + valid,
        "<page id=\"0:1\">" + valid + "</page>",
    ] { #expect(throws: DesignError.self) { try NodeGeometry.parse(xml: xml, expectedNodeID: "12:34") } }
}

@Test func rejectsTraversalAndSymlinkOutputs() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    for path in ["../outside", "/tmp/outside", "a/../../outside", "a//b", ".git/config", "a\\b"] {
        #expect(throws: DesignError.self) { try LocalFiles.resolve(path, beneath: root) }
    }
    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "/tmp")
    #expect(throws: DesignError.self) { try LocalFiles.resolve("link/output", beneath: root) }
    #expect(try LocalFiles.resolve("Preview Content/XRayReferences", beneath: root).lastPathComponent == "XRayReferences")
}

@Test func checksumAndGeometryMustMatchTheImportedPNG() throws {
    let source = try DesignSource(name: "example", figmaURL: sourceURL)
    let geometry = NodeGeometry(nodeID: "12:34", name: "Example", width: 2, height: 4)
    let png = try makePNG()
    let metadata = try ReferenceMetadata(source: source, geometry: geometry, png: png, serverVersion: "test")
    try metadata.validate(png: png, source: source)
    #expect(metadata.version == nil)
    #expect(metadata.exportScale == 1)
    #expect(throws: DesignError.self) { try metadata.validate(png: makePNG(red: 0), source: source) }
    #expect(throws: DesignError.self) {
        try ReferenceMetadata(source: source, geometry: NodeGeometry(nodeID: "12:34", name: "Example", width: 2, height: 12), png: png, serverVersion: "test")
    }
}

@Test func failedAndUnapprovedReplacementsPreservePreviousReference() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let resources = root.appendingPathComponent("XRayReferences")
    let catalog = root.appendingPathComponent("DesignReferences.generated.swift")
    let source = try DesignSource(name: "example", figmaURL: sourceURL)
    let geometry = NodeGeometry(nodeID: "12:34", name: "Example", width: 2, height: 4)
    let png = try makePNG()
    let metadata = try ReferenceMetadata(source: source, geometry: geometry, png: png, serverVersion: "test")
    let code = try LocalFiles.catalog(names: [source.name], subdirectory: "XRayReferences")
    try LocalFiles.publish(png: png, metadata: metadata, source: source, resourceRoot: resources, catalogURL: catalog, catalogData: code, replacing: false)
    let imagePath = resources.appendingPathComponent("example/reference.png")
    let metadataPath = resources.appendingPathComponent("example/metadata.json")
    let originalMetadata = try Data(contentsOf: metadataPath)
    #expect(throws: DesignError.self) {
        try LocalFiles.publish(png: png, metadata: metadata, source: source, resourceRoot: resources, catalogURL: catalog, catalogData: code, replacing: false)
    }
    #expect(throws: DesignError.self) {
        try LocalFiles.publish(png: makePNG(red: 0), metadata: metadata, source: source, resourceRoot: resources, catalogURL: catalog, catalogData: code, replacing: true)
    }
    #expect(try Data(contentsOf: imagePath) == png)
    #expect(try Data(contentsOf: metadataPath) == originalMetadata)
    #expect(try Data(contentsOf: catalog) == code)
    let newPNG = try makePNG(red: 0)
    let newMetadata = try ReferenceMetadata(source: source, geometry: geometry, png: newPNG, serverVersion: "test")
    try LocalFiles.publish(png: newPNG, metadata: newMetadata, source: source, resourceRoot: resources, catalogURL: catalog, catalogData: code, replacing: true)
    #expect(try Data(contentsOf: imagePath) == newPNG)
}

@Test func refusesToOverwriteAnUnownedCatalog() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try DesignSource(name: "example", figmaURL: sourceURL)
    let png = try makePNG()
    let metadata = try ReferenceMetadata(source: source, geometry: NodeGeometry(nodeID: "12:34", name: "Example", width: 2, height: 4), png: png, serverVersion: "test")
    let catalog = root.appendingPathComponent("Handwritten.swift")
    try Data("// Handwritten".utf8).write(to: catalog)
    #expect(throws: DesignError.self) {
        try LocalFiles.publish(png: png, metadata: metadata, source: source, resourceRoot: root.appendingPathComponent("XRayReferences"), catalogURL: catalog, catalogData: Data(), replacing: false)
    }
    #expect(try String(contentsOf: catalog, encoding: .utf8) == "// Handwritten")
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("XRayReferences/example").path))
}

@Test func handlesMCPResultIDsAndToolErrors() throws {
    let response = Data("{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{\"content\":[]}}".utf8)
    #expect(try MCPEnvelope.result(from: response, id: 3) == nil)
    #expect(try MCPEnvelope.result(from: response, id: 4) != nil)
    let error = Data("{\"id\":4,\"result\":{\"isError\":true,\"content\":[{\"type\":\"text\",\"text\":\"Missing node\"}]}}".utf8)
    #expect(throws: DesignError.self) { try MCPEnvelope.result(from: error, id: 4) }
    #expect(throws: DesignError.self) { try MCPEnvelope.png(from: ["content": []]) }
    let protocolError = Data(#"{"id":4,"error":{"code":-32603,"message":"Open an active design tab."}}"#.utf8)
    do {
        _ = try MCPEnvelope.result(from: protocolError, id: 4)
        Issue.record("Expected a protocol error")
    } catch {
        #expect(error.localizedDescription.contains("Open an active design tab."))
    }
}

@Test func acceptsFractionalCaptureDatesAndEscapesGeneratedIdentifiers() throws {
    #expect(ReferenceMetadata.captureDate("2026-09-27T09:02:30.807738+00:00") != nil)
    #expect(ReferenceMetadata.captureDate("2026-09-27T09:02:30Z") != nil)
    let text = String(decoding: try LocalFiles.catalog(names: ["precedencegroup"], subdirectory: "XRayReferences"), as: UTF8.self)
    #expect(text.contains("static func `precedencegroup`(bundle: Bundle)"))
    #expect(throws: DesignError.self) { try LocalFiles.catalog(names: ["example"], subdirectory: "bad\"folder") }
}

@Test func catalogWriteFailureRestoresPreviousReference() throws {
    let fm = FileManager.default
    let root = try temporaryDirectory()
    let resources = root.appendingPathComponent("XRayReferences")
    let catalogRoot = root.appendingPathComponent("Catalog")
    let catalog = catalogRoot.appendingPathComponent("DesignReferences.generated.swift")
    defer {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: catalogRoot.path)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: catalog.path)
        try? fm.removeItem(at: root)
    }
    let source = try DesignSource(name: "example", figmaURL: sourceURL)
    let geometry = NodeGeometry(nodeID: "12:34", name: "Example", width: 2, height: 4)
    let oldPNG = try makePNG()
    let oldMetadata = try ReferenceMetadata(source: source, geometry: geometry, png: oldPNG, serverVersion: "test")
    let oldCode = try LocalFiles.catalog(names: [source.name], subdirectory: "XRayReferences")
    try LocalFiles.publish(png: oldPNG, metadata: oldMetadata, source: source, resourceRoot: resources, catalogURL: catalog, catalogData: oldCode, replacing: false)
    let imageURL = resources.appendingPathComponent("example/reference.png")
    let metadataURL = resources.appendingPathComponent("example/metadata.json")
    let oldMetadataBytes = try Data(contentsOf: metadataURL)
    let newPNG = try makePNG(red: 0)
    let newMetadata = try ReferenceMetadata(source: source, geometry: geometry, png: newPNG, serverVersion: "test")
    let newCode = oldCode + Data("\n// New catalog revision\n".utf8)
    try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: catalog.path)
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: catalogRoot.path)
    #expect(throws: (any Error).self) {
        try LocalFiles.publish(png: newPNG, metadata: newMetadata, source: source, resourceRoot: resources, catalogURL: catalog, catalogData: newCode, replacing: true)
    }
    #expect(try Data(contentsOf: imageURL) == oldPNG)
    #expect(try Data(contentsOf: metadataURL) == oldMetadataBytes)
    #expect(try Data(contentsOf: catalog) == oldCode)
    #expect(try fm.contentsOfDirectory(atPath: resources.path) == [source.name])
}

@Test func rejectsCaseInsensitiveReferenceNameCollisions() throws {
    let first = try DesignSource(name: "noteInput", figmaURL: sourceURL)
    let second = try DesignSource(name: "noteinput", figmaURL: sourceURL)
    let registry = DesignRegistry(resourceDirectory: "XRayReferences", swiftCatalog: "References.swift", references: [first, second])
    #expect(throws: DesignError.self) { try registry.validate() }
}
