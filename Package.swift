// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KnobsCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KnobsCore", targets: ["KnobsCore"])
    ],
    targets: [
        .target(name: "KnobsCore"),
        // Fixtures are read from disk by path (see Support/Fixtures.swift), not bundled as resources.
        .testTarget(name: "KnobsCoreTests", dependencies: ["KnobsCore"], exclude: ["Fixtures"]),
    ]
)
