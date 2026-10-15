// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Snipper",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Snipper"),
        .testTarget(name: "SnipperTests", dependencies: ["Snipper"]),
    ]
)
