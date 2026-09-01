import Foundation
import PaceCore

public struct CodexProfile: Equatable, Sendable {
    public let directory: URL
    public let ownership: ProfileOwnership
    public let displayName: String?

    public init(
        directory: URL,
        ownership: ProfileOwnership,
        displayName: String? = nil,
    ) {
        self.directory = directory.standardizedFileURL
        self.ownership = ownership
        self.displayName = displayName
    }
}

struct CodexAccountPayload: Decodable, Equatable, Sendable {
    let email: String?
    let planType: String?
    let type: String
}

struct CodexAccountResponse: Decodable, Equatable, Sendable {
    let account: CodexAccountPayload?
    let requiresOpenaiAuth: Bool
}

struct CodexRateLimitWindow: Decodable, Equatable, Sendable {
    let resetsAt: Int64?
    let usedPercent: Int
    let windowDurationMins: Int64?
}

struct CodexRateLimitSnapshot: Decodable, Equatable, Sendable {
    let limitID: String?
    let limitName: String?
    let planType: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case planType
        case primary
        case secondary
    }
}

struct CodexRateLimitsResponse: Decodable, Equatable, Sendable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitID: [String: CodexRateLimitSnapshot]?

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
    }
}

struct CodexProfileSnapshot: Equatable, Sendable {
    let account: CodexAccountResponse
    let rateLimits: CodexRateLimitsResponse?
}

enum CodexProviderError: Error, Equatable, Sendable {
    case executableUnavailable
    case invalidAccount
    case invalidResponse
    case processFailed
    case protocolFailure(code: Int)
    case signedOut
    case timedOut
}
