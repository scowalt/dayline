// swift-tools-version: 6.2

import PackageDescription

let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Dayline",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "Dayline", targets: ["Dayline"]),
        .library(name: "DaylineWidget", targets: ["DaylineWidget"]),
    ],
    dependencies: [
        .package(path: "Core"),
    ],
    targets: [
        .target(
            name: "Dayline",
            dependencies: ["DaylineKit", .product(name: "DaylineCore", package: "Core")],
            swiftSettings: approachableConcurrency + [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "DaylineWidget",
            dependencies: ["DaylineKit", .product(name: "DaylineCore", package: "Core")],
            swiftSettings: approachableConcurrency + [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]
        ),
        .target(
            name: "DaylineKit",
            dependencies: [.product(name: "DaylineCore", package: "Core")],
            swiftSettings: approachableConcurrency
        ),
    ]
)
