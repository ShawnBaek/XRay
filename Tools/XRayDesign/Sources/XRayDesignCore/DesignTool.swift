import Foundation

public enum DesignTool {
    static let help = """
    xray design doctor
    xray design add <name> --figma <node-URL> [--manifest <path>]
        [--resources <relative-directory>] [--catalog <relative-Swift-file>] [--replace]
    xray design sync <name> --confirm-open-file <file-or-branch-key>
        [--manifest <path>] [--replace]
    xray design import <name> --png <path> --metadata <path>
        [--manifest <path>] [--replace]

    The manifest defaults to xray-design.json in the current directory.
    First check the personal account and exact source file in Figma Desktop.
    Sync reads only http://127.0.0.1:3845/mcp; it cannot verify the active file/account.
    --confirm-open-file is your explicit confirmation of that check for this capture.
    Desktop snapshots are timestamped and hashed, not pinned to a Figma file version.
    Import accepts only previously captured PNG + xray metadata with a matching checksum.
    Existing references are preserved unless --replace is supplied.
    """

    @MainActor public static func run(arguments: [String]) async throws -> String {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["design", "--help"] { return help }
        guard arguments.count >= 2, arguments[0] == "design" else { throw DesignError(help) }
        let command = arguments[1]
        let options = try Options(Array(arguments.dropFirst(2)))
        if command == "doctor" {
            try options.allow([], positionalCount: 0)
            let client = DesktopMCP()
            try await client.connect()
            return "Figma Desktop MCP \(client.serverVersion) is reachable; metadata and screenshot tools are available. Account and file identity require checking the desktop app."
        }
        guard ["add", "sync", "import"].contains(command) else { throw DesignError(help) }
        let allowed: Set<String> = command == "add"
            ? ["figma", "manifest", "resources", "catalog", "replace"]
            : command == "sync" ? ["manifest", "confirm-open-file", "replace"]
            : ["manifest", "png", "metadata", "replace"]
        try options.allow(allowed, positionalCount: 1)
        let name = options.positionals[0]
        let manifest = URL(fileURLWithPath: options.values["manifest"] ?? "xray-design.json").standardizedFileURL
        let base = manifest.deletingLastPathComponent()
        var registry: DesignRegistry
        if FileManager.default.fileExists(atPath: manifest.path) {
            registry = try JSONDecoder().decode(DesignRegistry.self, from: LocalFiles.read(manifest, limit: 1_000_000))
            try registry.validate()
        } else {
            guard command == "add" else { throw DesignError("Register a reference with design add first.") }
            registry = DesignRegistry(resourceDirectory: options.values["resources"] ?? "PreviewContent/XRayReferences",
                                      swiftCatalog: options.values["catalog"] ?? "PreviewContent/DesignReferences.generated.swift", references: [])
        }
        let resourceRoot = try LocalFiles.resolve(registry.resourceDirectory, beneath: base)
        let catalogURL = try LocalFiles.resolve(registry.swiftCatalog, beneath: base)
        guard catalogURL.pathExtension == "swift", catalogURL != manifest,
              !catalogURL.path.hasPrefix(resourceRoot.path + "/") else {
            throw DesignError("The generated Swift catalog must be outside the resource directory and separate from the manifest.")
        }
        if command == "add" {
            if let resources = options.values["resources"], resources != registry.resourceDirectory {
                throw DesignError("The manifest already has a resource directory. Edit that setting deliberately before adding references.")
            }
            if let catalog = options.values["catalog"], catalog != registry.swiftCatalog {
                throw DesignError("The manifest already has a Swift catalog path. Edit that setting deliberately before adding references.")
            }
            guard let figma = options.values["figma"] else { throw DesignError("design add requires --figma <node-URL>.") }
            let source = try DesignSource(name: name, figmaURL: figma)
            if registry.references.contains(where: { $0.name == name }) && !options.replace {
                throw DesignError("This reference is already registered. Use --replace to change its source.")
            }
            registry.references.removeAll { $0.name == name }
            registry.references.append(source)
            registry.references.sort { $0.name < $1.name }
            try registry.validate()
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try LocalFiles.encode(registry).write(to: manifest, options: .atomic)
            return "Registered \(name). Open its source in Figma Desktop, verify the account/file, then run design sync with --confirm-open-file \(source.fileKey)."
        }
        guard let source = registry.references.first(where: { $0.name == name }) else {
            throw DesignError("No reference named \(name) is registered.")
        }
        try LocalFiles.checkDestination(resourceRoot.appendingPathComponent(name), replacing: options.replace)
        let png: Data
        let metadata: ReferenceMetadata
        if command == "sync" {
            try source.confirm(openFile: options.values["confirm-open-file"])
            let client = DesktopMCP()
            try await client.connect()
            (png, metadata) = try await client.capture(source: source)
        } else {
            guard let pngPath = options.values["png"], let metadataPath = options.values["metadata"] else {
                throw DesignError("design import requires --png and --metadata from a prior desktop capture.")
            }
            png = try LocalFiles.read(URL(fileURLWithPath: pngPath), limit: 64_000_000)
            metadata = try JSONDecoder().decode(ReferenceMetadata.self, from: LocalFiles.read(URL(fileURLWithPath: metadataPath), limit: 128_000))
            try metadata.validate(png: png, source: source)
        }
        let names = registry.references.filter {
            $0.name == name || FileManager.default.fileExists(atPath: resourceRoot.appendingPathComponent($0.name).appendingPathComponent("metadata.json").path)
        }.map(\.name)
        let catalog = try LocalFiles.catalog(names: names, subdirectory: resourceRoot.lastPathComponent)
        try LocalFiles.publish(png: png, metadata: metadata, source: source, resourceRoot: resourceRoot,
                               catalogURL: catalogURL, catalogData: catalog, replacing: options.replace)
        return "Imported \(name): \(metadata.pixelWidth) × \(metadata.pixelHeight) PNG, \(metadata.logicalWidth) × \(metadata.logicalHeight) point canvas. Add the resource folder and generated catalog to their owning preview target."
    }
}

private struct Options {
    var values: [String: String] = [:]
    var positionals: [String] = []
    var replace = false

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let value = arguments[index]
            if value == "--replace" {
                guard !replace else { throw DesignError("Duplicate --replace option.") }
                replace = true
            } else if value.hasPrefix("--") {
                let key = String(value.dropFirst(2))
                guard values[key] == nil, index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else { throw DesignError("Missing or duplicate value for \(value).") }
                index += 1
                values[key] = arguments[index]
            } else { positionals.append(value) }
            index += 1
        }
    }

    func allow(_ allowed: Set<String>, positionalCount: Int) throws {
        guard Set(values.keys).isSubset(of: allowed), (!replace || allowed.contains("replace")),
              positionals.count == positionalCount else { throw DesignError(DesignTool.help) }
    }
}
