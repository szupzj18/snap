// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snapkit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Snapkit", targets: ["Snapkit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        // Pure logic: models, geometry, settings, file output. No windows.
        .target(name: "SnapkitCore"),
        // The menu bar app: wires capture, overlays and windows together.
        .executableTarget(
            name: "Snapkit",
            dependencies: [
                "SnapkitCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "SnapkitCoreTests", dependencies: ["SnapkitCore"]),
    ]
)
