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
        .testTarget(name: "KnobsCoreTests", dependencies: ["KnobsCore"]),
    ]
)
