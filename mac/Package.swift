// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacClip",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MacClipCore"),
        .executableTarget(name: "MacClip", dependencies: ["MacClipCore"]),
        .executableTarget(name: "macclip-send", dependencies: ["MacClipCore"]),
        .testTarget(name: "MacClipCoreTests", dependencies: ["MacClipCore"]),
    ]
)
