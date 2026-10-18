// swift-tools-version: 6.3
// The Linux app: GTK 4 and libadwaita through Adwaita for Swift, sharing KnobsCore and KnobsSession with the
// Mac app (DEC-014). Built only in a local container: `scripts/linux.sh build`.
import PackageDescription

let package = Package(
    name: "KnobsLinux",
    products: [
        .executable(name: "knobs", targets: ["Knobs"])
    ],
    dependencies: [
        .package(path: ".."),
        // No tags after 0.1.0 at its current home, so pinned by commit. Package.resolved is committed because
        // three of its own dependencies follow a branch.
        .package(
            url: "https://codeberg.org/aparoksha/adwaita-swift",
            revision: "af5598fbd6f2425841f426ad388d7a7edd6c90e6"),
    ],
    targets: [
        .executableTarget(
            name: "Knobs",
            dependencies: [
                .product(name: "KnobsCore", package: "knobs"),
                .product(name: "KnobsSession", package: "knobs"),
                .product(name: "Adwaita", package: "adwaita-swift"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
