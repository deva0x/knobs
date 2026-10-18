// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KnobsCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KnobsCore", targets: ["KnobsCore"]),
        // What both apps share above the core: each task's live state, and the Toolbox of tools, sessions and
        // saved settings.
        .library(name: "KnobsSession", targets: ["KnobsSession"]),
    ],
    targets: [
        .target(name: "KnobsCore"),
        .target(name: "KnobsSession", dependencies: ["KnobsCore"]),
        // Fixtures are read from disk by path (see Support/Fixtures.swift), not bundled as resources.
        .testTarget(name: "KnobsCoreTests", dependencies: ["KnobsCore"], exclude: ["Fixtures"]),
        .testTarget(name: "KnobsSessionTests", dependencies: ["KnobsCore", "KnobsSession"]),
    ]
)
