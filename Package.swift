// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MacDictationNotion",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Pure-logic library — testable, no AppKit
        .target(
            name: "MacDictationNotionCore",
            path: "Sources/MacDictationNotionCore"
        ),
        // App executable — AppKit UI, depends on Core
        .executableTarget(
            name: "MacDictationNotion",
            dependencies: ["MacDictationNotionCore"],
            path: "Sources/MacDictationNotion"
        ),
        // Unit tests for Core logic
        .testTarget(
            name: "MacDictationNotionTests",
            dependencies: ["MacDictationNotionCore"],
            path: "Tests/MacDictationNotionTests"
        ),
    ]
)
