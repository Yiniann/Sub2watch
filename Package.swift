// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sub2WatchCore",
    platforms: [
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "Sub2WatchCore", targets: ["Sub2WatchCore"]),
    ],
    targets: [
        .target(
            name: "Sub2WatchCore",
            path: "Sources/Sub2WatchCore"
        ),
        .testTarget(
            name: "Sub2WatchCoreTests",
            dependencies: ["Sub2WatchCore"],
            path: "Tests/Sub2WatchCoreTests"
        ),
    ]
)
