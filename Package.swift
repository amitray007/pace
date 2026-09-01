// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Pace",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "PaceCore", targets: ["PaceCore"]),
        .library(name: "PaceProviders", targets: ["PaceProviders"]),
        .executable(name: "PaceApp", targets: ["PaceApp"]),
        .executable(name: "pace-benchmark", targets: ["PaceBenchmark"]),
        .executable(name: "claude-usage-spike", targets: ["ClaudeUsageSpike"]),
        .executable(name: "cursor-usage-spike", targets: ["CursorUsageSpike"]),
        .executable(name: "grok-usage-spike", targets: ["GrokUsageSpike"]),
        .executable(
            name: "github-copilot-usage-spike",
            targets: ["GitHubCopilotUsageSpike"],
        ),
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
        .target(
            name: "PaceProviders",
            dependencies: ["PaceCore"],
        ),
        .executableTarget(
            name: "PaceApp",
            dependencies: ["PaceCore", "PaceProviders"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ],
        ),
        .testTarget(
            name: "PaceCoreTests",
            dependencies: ["PaceCore"],
        ),
        .testTarget(
            name: "PaceProviderTests",
            dependencies: ["PaceProviders", "PaceCore"],
        ),
        .executableTarget(
            name: "PaceBenchmark",
            dependencies: ["PaceCore"],
            path: "Benchmarks/PaceBenchmark",
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
        .target(
            name: "GrokUsageSpikeCore",
            path: "spikes/grok-usage/Sources/GrokUsageSpikeCore",
        ),
        .executableTarget(
            name: "GrokUsageSpike",
            dependencies: ["GrokUsageSpikeCore"],
            path: "spikes/grok-usage/Sources/GrokUsageSpike",
        ),
        .testTarget(
            name: "GrokUsageSpikeTests",
            dependencies: ["GrokUsageSpikeCore"],
            path: "spikes/grok-usage/Tests/GrokUsageSpikeTests",
        ),
        .target(
            name: "GitHubCopilotUsageSpikeCore",
            path: "spikes/github-copilot-usage/Sources/GitHubCopilotUsageSpikeCore",
        ),
        .executableTarget(
            name: "GitHubCopilotUsageSpike",
            dependencies: ["GitHubCopilotUsageSpikeCore"],
            path: "spikes/github-copilot-usage/Sources/GitHubCopilotUsageSpike",
        ),
        .testTarget(
            name: "GitHubCopilotUsageSpikeTests",
            dependencies: ["GitHubCopilotUsageSpikeCore"],
            path: "spikes/github-copilot-usage/Tests/GitHubCopilotUsageSpikeTests",
        ),
    ],
    swiftLanguageModes: [.v6],
)
