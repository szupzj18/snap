// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Snap", targets: ["Snap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        // Pure logic: models, geometry, settings, file output. No windows.
        .target(name: "SnapCore"),
        // ScreenCaptureKit wrappers and permission handling.
        .target(name: "SnapCapture", dependencies: ["SnapCore"]),
        // Annotation model, renderer and editor UI.
        .target(name: "SnapAnnotate", dependencies: ["SnapCore"]),
        // The menu bar app: wires capture, overlays and windows together.
        .executableTarget(
            name: "Snap",
            dependencies: [
                "SnapCore",
                "SnapCapture",
                "SnapAnnotate",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "SnapCoreTests", dependencies: ["SnapCore"]),
        .testTarget(name: "SnapAnnotateTests", dependencies: ["SnapAnnotate"]),
        // Takes real screenshots; skipped unless SNAP_INTEGRATION=1 (needs Screen Recording access).
        .testTarget(name: "SnapCaptureTests", dependencies: ["SnapCapture"]),
    ]
)
