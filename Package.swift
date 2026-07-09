// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MacDictationNotion",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MacDictationNotion",
            path: "Sources/MacDictationNotion"
        )
    ]
)
