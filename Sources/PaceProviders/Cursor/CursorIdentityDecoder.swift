import Foundation

struct CursorRemoteIdentity: Equatable, Sendable {
    let identity: CursorIdentity
    let authenticationID: String
}

enum CursorIdentityDecoder {
    static func decode(_ data: Data) throws(CursorProviderError) -> CursorRemoteIdentity {
        let response: CursorIdentityEnvelope
        do {
            response = try JSONDecoder().decode(CursorIdentityEnvelope.self, from: data)
        } catch {
            throw .invalidResponse
        }
        guard let userID = string(from: response.userID),
              !userID.isEmpty,
              !response.authenticationID.isEmpty
        else {
            throw .invalidResponse
        }
        let displayName = [response.firstName, response.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return CursorRemoteIdentity(
            identity: CursorIdentity(
                userID: userID,
                teamID: string(from: response.teamID),
                email: response.email,
                displayName: displayName.isEmpty ? nil : displayName,
            ),
            authenticationID: response.authenticationID,
        )
    }

    private static func string(from value: CursorStringOrNumber?) -> String? {
        switch value {
        case let .string(string):
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        case let .number(number):
            return NSDecimalNumber(decimal: number).stringValue
        case nil:
            return nil
        }
    }
}

private struct CursorIdentityEnvelope: Decodable {
    let authenticationID: String
    let email: String?
    let userID: CursorStringOrNumber?
    let firstName: String?
    let lastName: String?
    let teamID: CursorStringOrNumber?

    enum CodingKeys: String, CodingKey {
        case authenticationID = "authId"
        case email
        case userID = "userId"
        case firstName
        case lastName
        case teamID = "teamId"
    }
}

private enum CursorStringOrNumber: Decodable {
    case number(Decimal)
    case string(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = try .number(container.decode(Decimal.self))
        }
    }
}
