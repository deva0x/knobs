// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KnobsCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KnobsCore", targets: ["KnobsCore"]),
        // A task's live state, shared by the Mac and Linux apps: values, the command, and the current run.
        .library(name: "KnobsSession", targets: ["KnobsSession"]),
    ],
    targets: [
        .target(name: "KnobsCore"),
        .target(name: "KnobsSession", dependencies: ["KnobsCore"]),
        // Fixtures are read from disk by path (see Support/Fixtures.swift), not bundled as resources.
        .testTarget(name: "KnobsCoreTests", dependencies: ["KnobsCore"], exclude: ["Fixtures"]),
    ]
)
