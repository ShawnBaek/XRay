// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XRay",
    platforms: [.iOS(.v17)],
    products: [.library(name: "XRay", targets: ["XRay"])],
    targets: [
        .target(name: "XRay"),
        .testTarget(name: "XRayTests", dependencies: ["XRay"]),
    ]
)
