// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XRayDesign",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "xray", targets: ["xray"])],
    targets: [
        .target(name: "XRayDesignCore"),
        .executableTarget(name: "xray", dependencies: ["XRayDesignCore"]),
        .testTarget(name: "XRayDesignCoreTests", dependencies: ["XRayDesignCore"]),
    ]
)
