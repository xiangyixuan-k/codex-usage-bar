// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsageBar", targets: ["CodexUsageBar"]),
        .library(name: "CodexUsageBarCore", targets: ["CodexUsageBarCore"])
    ],
    targets: [
        .target(name: "CodexUsageBarCore"),
        .executableTarget(
            name: "CodexUsageBar",
            dependencies: ["CodexUsageBarCore"]
        )
    ]
)
