// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PocketPaste",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PocketPasteCore"),
        .executableTarget(name: "PocketPaste", dependencies: ["PocketPasteCore"]),
        .executableTarget(name: "pocketpaste-send", dependencies: ["PocketPasteCore"]),
        .testTarget(name: "PocketPasteCoreTests", dependencies: ["PocketPasteCore"]),
    ]
)
