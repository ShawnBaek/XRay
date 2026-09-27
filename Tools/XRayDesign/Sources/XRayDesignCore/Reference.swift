import CryptoKit
import Darwin
import Foundation
import ImageIO

struct DesignError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct DesignSource: Codable, Equatable {
    let name: String
    let sourceURL: String
    let fileKey: String
    let nodeID: String

    init(name: String, figmaURL: String) throws {
        let reserved = Set("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as any catch false is nil super self Self throw throws true try async await some bundle".split(separator: " ").map(String.init))
        guard name.range(of: "^[a-z][A-Za-z0-9_]*$", options: .regularExpression) != nil,
              !reserved.contains(name) else { throw DesignError("Choose a reference name such as referenceCrumbInput, using letters, digits, and underscores.") }
        guard let url = URLComponents(string: figmaURL), url.scheme == "https",
              ["figma.com", "www.figma.com"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil else {
            throw DesignError("Use an HTTPS node link from figma.com.")
        }
        let path = url.path.split(separator: "/").map(String.init)
        guard path.count >= 2, ["design", "file"].contains(path[0]) else {
            throw DesignError("Use a Figma Design file or node link.")
        }
        let key: String
        if path.count >= 3 && path[2] == "branch" {
            guard path.count >= 4 else { throw DesignError("The Figma branch link is incomplete.") }
            key = path[3]
        } else { key = path[1] }
        guard key.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            throw DesignError("The Figma file key is invalid.")
        }
        let nodes = (url.queryItems ?? []).filter { $0.name == "node-id" }
        guard nodes.count == 1, let node = nodes[0].value,
              node.range(of: "^[0-9]+[:-][0-9]+$", options: .regularExpression) != nil else {
            throw DesignError("The Figma link must contain one numeric node-id, such as 12-34.")
        }
        self.name = name
        sourceURL = figmaURL
        fileKey = key
        nodeID = node.replacingOccurrences(of: "-", with: ":")
    }

    func validate() throws {
        guard try Self(name: name, figmaURL: sourceURL) == self else {
            throw DesignError("The registered Figma link and node identifiers do not agree.")
        }
    }

    func confirm(openFile: String?) throws {
        guard openFile == fileKey else {
            throw DesignError("Open this source in the signed-in Figma Desktop app, check its account and file, then pass --confirm-open-file \(fileKey). Desktop MCP cannot verify the open file or account.")
        }
    }
}

struct DesignRegistry: Codable {
    var schemaVersion = 1
    var resourceDirectory: String
    var swiftCatalog: String
    var references: [DesignSource]

    func validate() throws {
        guard schemaVersion == 1, Set(references.map { $0.name.lowercased() }).count == references.count else {
            throw DesignError("Invalid or unsupported design registration manifest.")
        }
        try references.forEach { try $0.validate() }
    }
}

struct NodeGeometry: Equatable {
    let nodeID: String
    let name: String
    let width: Double
    let height: Double

    static func parse(xml: String, expectedNodeID: String) throws -> Self {
        guard xml.utf8.count <= 2_000_000,
              !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else {
            throw DesignError("Unsupported or oversized desktop metadata XML.")
        }
        let delegate = GeometryParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let attributes = delegate.root,
              attributes["id"] == expectedNodeID,
              attributes["hidden"] != "true",
              let width = Double(attributes["width"] ?? ""),
              let height = Double(attributes["height"] ?? ""),
              width.isFinite, height.isFinite,
              width > 0, height > 0, width <= 16_384, height <= 16_384 else {
            throw DesignError("Desktop metadata must describe the requested visible node with finite, positive dimensions.")
        }
        return Self(nodeID: expectedNodeID, name: attributes["name"] ?? "", width: width, height: height)
    }
}

private final class GeometryParser: NSObject, XMLParserDelegate {
    var root: [String: String]?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if root == nil { root = attributeDict }
    }
}

struct ReferenceMetadata: Codable, Equatable {
    let schemaVersion: Int
    let sourceURL: String
    let fileKey: String
    let nodeID: String
    let version: String?
    let logicalWidth: Double
    let logicalHeight: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let exportScale: Double
    let sha256: String
    let provenance: String
    let capturedAt: String
    let serverVersion: String

    init(source: DesignSource, geometry: NodeGeometry, png: Data, serverVersion: String, capturedAt: Date = Date()) throws {
        try source.validate()
        guard source.nodeID == geometry.nodeID else { throw DesignError("Metadata belongs to a different node.") }
        let dimensions = try Self.pngDimensions(png)
        let scale = Double(dimensions.width) / geometry.width
        guard scale.isFinite, scale > 0, scale <= 4,
              abs(Double(dimensions.height) - geometry.height * scale) <= 1 else {
            throw DesignError("Screenshot dimensions do not match the design canvas or supported scale (up to 4x).")
        }
        schemaVersion = 1
        sourceURL = source.sourceURL
        fileKey = source.fileKey
        nodeID = source.nodeID
        version = nil // Desktop MCP does not expose or pin a Figma file version.
        logicalWidth = geometry.width
        logicalHeight = geometry.height
        pixelWidth = dimensions.width
        pixelHeight = dimensions.height
        exportScale = scale
        sha256 = Self.digest(png)
        provenance = "figma-desktop-mcp"
        self.capturedAt = ISO8601DateFormatter().string(from: capturedAt)
        self.serverVersion = serverVersion
    }

    func validate(png: Data, source: DesignSource) throws {
        try source.validate()
        guard schemaVersion == 1, provenance == "figma-desktop-mcp", version == nil,
              sourceURL == source.sourceURL, fileKey == source.fileKey, nodeID == source.nodeID,
              logicalWidth.isFinite, logicalHeight.isFinite, logicalWidth > 0, logicalHeight > 0,
              logicalWidth <= 16_384, logicalHeight <= 16_384,
              exportScale.isFinite, exportScale > 0, exportScale <= 4,
              Self.captureDate(capturedAt) != nil,
              !serverVersion.isEmpty, Self.digest(png) == sha256 else {
            throw DesignError("Reference metadata, provenance, or checksum does not match the PNG and registered source.")
        }
        let dimensions = try Self.pngDimensions(png)
        guard dimensions.width == pixelWidth, dimensions.height == pixelHeight,
              abs(Double(pixelWidth) - logicalWidth * exportScale) <= 1,
              abs(Double(pixelHeight) - logicalHeight * exportScale) <= 1 else {
            throw DesignError("Reference PNG dimensions do not match its metadata.")
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func captureDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func pngDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        guard data.count <= 64_000_000,
              let image = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(image) as String? == "public.png",
              CGImageSourceGetCount(image) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 16_000_000,
              CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else {
            throw DesignError("Expected one valid PNG image, at most 16 megapixels and 64 MB.")
        }
        return (width, height)
    }
}

enum LocalFiles {
    static let generatedHeader = "// Generated by xray design. Do not edit."

    static func resolve(_ relative: String, beneath root: URL) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else {
            throw DesignError("Output paths must be relative to the manifest, without hidden directories or traversal.")
        }
        var result = root.standardizedFileURL.resolvingSymlinksInPath()
        for part in parts {
            result.appendPathComponent(String(part))
            if (try? result.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw DesignError("Output paths cannot contain symbolic links.")
            }
        }
        return result
    }

    static func read(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let count = values.fileSize, count <= limit else {
            throw DesignError("Expected a regular file within the supported size limit: \(url.lastPathComponent).")
        }
        return try Data(contentsOf: url)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func catalog(names: [String], subdirectory: String) throws -> Data {
        guard subdirectory.range(of: "^[A-Za-z][A-Za-z0-9 _-]*$", options: .regularExpression) != nil,
              names.allSatisfy({ $0.range(of: "^[a-z][A-Za-z0-9_]*$", options: .regularExpression) != nil }) else {
            throw DesignError("Catalog identifiers and resource folder names must use simple ASCII letters, digits, underscores, spaces, or hyphens.")
        }
        var text = "\(generatedHeader)\n#if DEBUG\nimport Foundation\nimport XRay\n\n@MainActor\nenum DesignReferences {\n"
        for name in names.sorted() {
            text += "    static func `\(name)`(bundle: Bundle) -> XRayPreviewReference {\n"
            text += "        .resource(\"\(name)\", bundle: bundle, subdirectory: \"\(subdirectory)\")\n    }\n"
        }
        return Data((text + "}\n#endif\n").utf8)
    }

    static func checkDestination(_ target: URL, replacing: Bool) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard replacing, values.isSymbolicLink != true, values.isDirectory == true else {
                throw DesignError("Reference already exists or is unsafe. Use --replace only to replace a previously imported reference.")
            }
            let names = try FileManager.default.contentsOfDirectory(atPath: target.path)
            guard Set(names) == ["metadata.json", "reference.png"] else {
                throw DesignError("Refusing to replace a directory that contains files outside an imported reference.")
            }
        }
    }

    static func publish(png: Data, metadata: ReferenceMetadata, source: DesignSource,
                        resourceRoot: URL, catalogURL: URL, catalogData: Data, replacing: Bool) throws {
        try metadata.validate(png: png, source: source)
        let fm = FileManager.default
        let target = resourceRoot.appendingPathComponent(source.name, isDirectory: true)
        try checkDestination(target, replacing: replacing)
        if fm.fileExists(atPath: catalogURL.path) {
            let old = try read(catalogURL, limit: 1_000_000)
            guard String(decoding: old, as: UTF8.self).hasPrefix(generatedHeader + "\n") else {
                throw DesignError("Refusing to overwrite a Swift file that was not generated by xray design.")
            }
        }
        try fm.createDirectory(at: resourceRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stage = resourceRoot.appendingPathComponent(".xray-stage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var preserveStage = false
        defer { if !preserveStage { try? fm.removeItem(at: stage) } }
        try png.write(to: stage.appendingPathComponent("reference.png"))
        try encode(metadata).write(to: stage.appendingPathComponent("metadata.json"))
        let existed = replacing && fm.fileExists(atPath: target.path)
        let flags = UInt32(existed ? RENAME_SWAP : RENAME_EXCL)
        guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, target.path, flags) == 0 else {
            throw DesignError("Could not atomically install the reference (filesystem error \(errno)).")
        }
        do { try catalogData.write(to: catalogURL, options: .atomic) }
        catch {
            // The old reference remains in stage until both output writes succeed.
            if existed {
                guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, target.path, UInt32(RENAME_SWAP)) == 0 else {
                    preserveStage = true
                    throw DesignError("Catalog write failed and automatic rollback failed. Previous reference is at \(stage.path).")
                }
            } else { try? fm.removeItem(at: target) }
            throw error
        }
    }
}
