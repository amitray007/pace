import Foundation

public struct ProviderID: RawRepresentable, Codable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public extension ProviderID {
    static let claude = Self(rawValue: "claude")
    static let codex = Self(rawValue: "codex")
    static let cursor = Self(rawValue: "cursor")
    static let githubCopilot = Self(rawValue: "github-copilot")
    static let grok = Self(rawValue: "grok")
}

public struct AccountID: RawRepresentable, Codable, Hashable, Sendable, Comparable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

public struct QuotaSubjectID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct BucketID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
