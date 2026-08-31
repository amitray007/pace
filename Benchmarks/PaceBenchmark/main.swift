import Foundation
import PaceCore

private struct BenchmarkConfiguration {
    let samples: Int
    let iterations: Int
    let maximumP95Milliseconds: Double?

    init(arguments: ArraySlice<String>) throws {
        var samples = 25
        var iterations = 20
        var maximumP95Milliseconds: Double?
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw BenchmarkError.missingValue(argument)
            }
            let value = arguments[valueIndex]

            switch argument {
            case "--samples":
                samples = try Self.positiveInteger(value, option: argument)
            case "--iterations":
                iterations = try Self.positiveInteger(value, option: argument)
            case "--max-p95-ms":
                guard let parsedValue = Double(value), parsedValue > 0 else {
                    throw BenchmarkError.invalidValue(option: argument, value: value)
                }
                maximumP95Milliseconds = parsedValue
            default:
                throw BenchmarkError.unknownOption(argument)
            }
            index = arguments.index(after: valueIndex)
        }

        self.samples = samples
        self.iterations = iterations
        self.maximumP95Milliseconds = maximumP95Milliseconds
    }

    private static func positiveInteger(_ value: String, option: String) throws -> Int {
        guard let parsedValue = Int(value), parsedValue > 0 else {
            throw BenchmarkError.invalidValue(option: option, value: value)
        }
        return parsedValue
    }
}

private struct BenchmarkReport: Encodable {
    let schemaVersion = 1
    let benchmark: String
    let buildConfiguration: String
    let samples: Int
    let iterationsPerSample: Int
    let medianMillisecondsPerOperation: Double
    let p95MillisecondsPerOperation: Double
    let minimumMillisecondsPerOperation: Double
    let maximumMillisecondsPerOperation: Double
    let checksum: Int
    let maximumP95Milliseconds: Double?
    let passed: Bool
}

enum BenchmarkError: Error, CustomStringConvertible {
    case invalidCommand(String?)
    case invalidValue(option: String, value: String)
    case missingValue(String)
    case regression(p95Milliseconds: Double, maximumMilliseconds: Double)
    case unknownOption(String)

    var description: String {
        switch self {
        case let .invalidCommand(command):
            "Unknown benchmark command: \(command ?? "none"). Use `core` or `visual`."
        case let .invalidValue(option, value):
            "Invalid value for \(option): \(value)"
        case let .missingValue(option):
            "Missing value for \(option)"
        case let .regression(p95Milliseconds, maximumMilliseconds):
            "Benchmark regression: p95 \(p95Milliseconds) ms exceeded \(maximumMilliseconds) ms"
        case let .unknownOption(option):
            "Unknown benchmark option: \(option)"
        }
    }
}

@main
private enum PaceBenchmark {
    static func main() async {
        do {
            let arguments = CommandLine.arguments.dropFirst()
            guard let command = arguments.first else {
                throw BenchmarkError.invalidCommand(arguments.first)
            }
            switch command {
            case "core":
                let configuration = try BenchmarkConfiguration(arguments: arguments.dropFirst())
                let report = try await benchmarkCore(configuration: configuration)
                try write(report)
                guard report.passed else {
                    throw BenchmarkError.regression(
                        p95Milliseconds: report.p95MillisecondsPerOperation,
                        maximumMilliseconds: configuration.maximumP95Milliseconds ?? 0,
                    )
                }
            case "visual":
                try write(runVisualBenchmark(arguments: arguments.dropFirst()))
            default:
                throw BenchmarkError.invalidCommand(command)
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func benchmarkCore(
        configuration: BenchmarkConfiguration,
    ) async throws -> BenchmarkReport {
        var checksum = 0
        for _ in 0 ..< 3 {
            checksum &+= try await runVisualReferencePipeline()
        }

        let clock = ContinuousClock()
        var millisecondsPerOperation: [Double] = []
        millisecondsPerOperation.reserveCapacity(configuration.samples)

        for _ in 0 ..< configuration.samples {
            let start = clock.now
            for _ in 0 ..< configuration.iterations {
                checksum &+= try await runVisualReferencePipeline()
            }
            let elapsed = start.duration(to: clock.now)
            millisecondsPerOperation.append(
                elapsed.milliseconds / Double(configuration.iterations),
            )
        }

        let sorted = millisecondsPerOperation.sorted()
        let median = percentile(0.5, values: sorted)
        let p95 = percentile(0.95, values: sorted)
        let maximumP95 = configuration.maximumP95Milliseconds
        return BenchmarkReport(
            benchmark: "visual-reference-seed-refresh-read",
            buildConfiguration: "release",
            samples: configuration.samples,
            iterationsPerSample: configuration.iterations,
            medianMillisecondsPerOperation: median,
            p95MillisecondsPerOperation: p95,
            minimumMillisecondsPerOperation: sorted[0],
            maximumMillisecondsPerOperation: sorted[sorted.count - 1],
            checksum: checksum,
            maximumP95Milliseconds: maximumP95,
            passed: maximumP95.map { p95 <= $0 } ?? true,
        )
    }

    private static func runVisualReferencePipeline() async throws -> Int {
        let scenario = try SimulatedScenarios.visualReference()
        let store = try await PaceStore.open(
            persistence: InMemoryPaceStatePersistence(),
        )
        try await scenario.seed(store)
        let coordinator = try RefreshCoordinator(store: store, adapters: scenario.adapters)
        let outcomes = try await coordinator.refreshAll()
        let state = await store.currentState()
        return state.accounts.count &+ state.snapshots.count &+ outcomes.count
    }

    private static func percentile(_ percentile: Double, values: [Double]) -> Double {
        let rank = Int(ceil(percentile * Double(values.count))) - 1
        return values[max(0, min(rank, values.count - 1))]
    }

    private static func write(_ report: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = components
        let seconds = Double(components.seconds) * 1000
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        return seconds + attoseconds
    }
}
