// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Pace",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "PaceCore", targets: ["PaceCore"]),
        .executable(name: "PaceApp", targets: ["PaceApp"]),
        .executable(name: "claude-usage-spike", targets: ["ClaudeUsageSpike"]),
        .executable(name: "cursor-usage-spike", targets: ["CursorUsageSpike"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/nicklockwood/SwiftFormat.git",
            exact: "0.62.1",
        ),
        .package(
            url: "https://github.com/SimplyDanny/SwiftLintPlugins.git",
            exact: "0.65.1",
        ),
    ],
    targets: [
        .target(name: "PaceCore"),
        .executableTarget(
            name: "PaceApp",
            dependencies: ["PaceCore"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ],
        ),
        .testTarget(
            name: "PaceCoreTests",
            dependencies: ["PaceCore"],
        ),
        .target(
            name: "ClaudeUsageSpikeCore",
            path: "spikes/claude-usage/Sources/ClaudeUsageSpikeCore",
        ),
        .executableTarget(
            name: "ClaudeUsageSpike",
            dependencies: ["ClaudeUsageSpikeCore"],
            path: "spikes/claude-usage/Sources/ClaudeUsageSpike",
        ),
        .testTarget(
            name: "ClaudeUsageSpikeTests",
            dependencies: ["ClaudeUsageSpikeCore"],
            path: "spikes/claude-usage/Tests/ClaudeUsageSpikeTests",
        ),
        .target(
            name: "CursorUsageSpikeCore",
            path: "spikes/cursor-usage/Sources/CursorUsageSpikeCore",
        ),
        .executableTarget(
            name: "CursorUsageSpike",
            dependencies: ["CursorUsageSpikeCore"],
            path: "spikes/cursor-usage/Sources/CursorUsageSpike",
        ),
        .testTarget(
            name: "CursorUsageSpikeTests",
            dependencies: ["CursorUsageSpikeCore"],
            path: "spikes/cursor-usage/Tests/CursorUsageSpikeTests",
        ),
    ],
    swiftLanguageModes: [.v6],
)
