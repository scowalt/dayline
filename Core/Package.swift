// swift-tools-version: 6.2

import PackageDescription

let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "DaylineCore", targets: ["DaylineCore"]),
    ],
    targets: [
        .target(name: "DaylineCore", swiftSettings: approachableConcurrency),
        .testTarget(
            name: "DaylineCoreTests",
            dependencies: ["DaylineCore"],
            swiftSettings: approachableConcurrency
        ),
    ]
)
