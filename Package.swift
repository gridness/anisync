// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AniSyncCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "AniSyncCore", targets: ["AniSyncCore"])],
    targets: [
        .target(name: "AniSyncCore", path: "Shared (Core)"),
        .testTarget(name: "AniSyncCoreTests", dependencies: ["AniSyncCore"], path: "Tests/AniSyncCoreTests")
    ]
)
