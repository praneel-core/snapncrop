// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snapncrop",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (geometry, annotations, undo, export). No windows, so it is unit-testable.
        .target(name: "SnapncropCore"),
        // The actual menu bar app (AppKit, ScreenCaptureKit, Carbon, MultitouchSupport).
        .executableTarget(name: "Snapncrop", dependencies: ["SnapncropCore"]),
        .testTarget(name: "SnapncropCoreTests", dependencies: ["SnapncropCore"]),
    ]
)
