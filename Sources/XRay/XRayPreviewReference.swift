import CryptoKit
import ImageIO
import UIKit

/// A local design image for an XRay preview. Loading never contacts the network.
@MainActor
public struct XRayPreviewReference {
    let identity: String
    private let loader: () throws -> XRayLoadedReference

    /// Uses an image already available to the caller.
    /// `logicalSize` is the design canvas in points, independent of PNG pixel density.
    public static func image(
        _ image: UIImage, logicalSize: CGSize, sourceURL: URL? = nil
    ) -> Self {
        Self(identity: "image:\(ObjectIdentifier(image)):\(logicalSize)") {
            guard validSize(logicalSize), image.cgImage != nil else {
                throw XRayReferenceError.invalidImage
            }
            return XRayLoadedReference(image: image, logicalSize: logicalSize, sourceURL: sourceURL)
        }
    }

    /// Loads a directory produced by `xray design sync` from its owning resource bundle.
    ///
    /// Keep the `XRayReferences` directory intact with SwiftPM's `.copy` resource rule
    /// or an Xcode folder resource. Pass the consumer's bundle, not XRay's bundle.
    public static func resource(
        _ name: String, bundle: Bundle, subdirectory: String = "XRayReferences"
    ) -> Self {
        Self(identity: "\(bundle.bundleURL.path)/\(subdirectory)/\(name)") {
            guard validComponent(name), validComponent(subdirectory),
                let resources = bundle.resourceURL
            else { throw XRayReferenceError.missingResource }
            let directory = resources.appendingPathComponent(subdirectory, isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            let metadataURL = directory.appendingPathComponent("metadata.json")
            guard let metadataSize = try? metadataURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                metadataSize <= 128_000,
                let metadataData = try? Data(contentsOf: metadataURL)
            else { throw XRayReferenceError.missingResource }
            let metadata = try JSONDecoder().decode(XRayReferenceMetadata.self, from: metadataData)
            let size = CGSize(width: metadata.logicalWidth, height: metadata.logicalHeight)
            guard metadata.schemaVersion == 1, validSize(size),
                metadata.exportScale.isFinite, metadata.exportScale > 0,
                metadata.exportScale <= 4, metadata.pixelWidth > 0, metadata.pixelHeight > 0,
                Double(metadata.pixelWidth) * Double(metadata.pixelHeight) <= 16_000_000
            else { throw XRayReferenceError.invalidMetadata }
            let imageURL = directory.appendingPathComponent("reference.png")
            guard let byteCount = try? imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                byteCount <= 64_000_000,
                let data = try? Data(contentsOf: imageURL),
                SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == metadata.sha256,
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                CGImageSourceGetType(source) as String? == "public.png",
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                width == metadata.pixelWidth, height == metadata.pixelHeight,
                abs(Double(width) - metadata.logicalWidth * metadata.exportScale) <= 1,
                abs(Double(height) - metadata.logicalHeight * metadata.exportScale) <= 1,
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw XRayReferenceError.invalidImage }
            return XRayLoadedReference(
                image: UIImage(cgImage: cgImage, scale: metadata.exportScale, orientation: .up),
                logicalSize: size, sourceURL: URL(string: metadata.sourceURL)
            )
        }
    }

    func load() throws -> XRayLoadedReference { try loader() }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
            && size.width <= 16_384 && size.height <= 16_384
    }

    private static func validComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\")
    }
}

struct XRayReferenceMetadata: Codable {
    let schemaVersion: Int
    let sourceURL: String
    let fileKey: String
    let nodeID: String
    let version: String?
    let provenance: String?
    let capturedAt: String?
    let serverVersion: String?
    let logicalWidth: Double
    let logicalHeight: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let exportScale: Double
    let sha256: String
}

struct XRayLoadedReference {
    let image: UIImage
    let logicalSize: CGSize
    let sourceURL: URL?
}

enum XRayReferenceError: LocalizedError {
    case missingResource, invalidMetadata, invalidImage

    var errorDescription: String? {
        switch self {
        case .missingResource: "Design reference is not synced or is missing from this resource bundle."
        case .invalidMetadata: "Design reference metadata is invalid or uses an unsupported format."
        case .invalidImage: "Design reference image is invalid or does not match its metadata. Sync it again."
        }
    }
}
