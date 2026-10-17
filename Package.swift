// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Snipper",
    platforms: [.macOS("26.0")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CZipReader", linkerSettings: [.linkedLibrary("archive")]),
        .executableTarget(name: "Snipper", dependencies: ["CSQLite", "CZipReader"]),
        .testTarget(name: "SnipperTests", dependencies: ["Snipper"]),
    ]
)
