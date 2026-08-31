import Foundation

struct CursorRemoteIdentity: Equatable, Sendable {
    let identity: CursorIdentity
    let authID: String
}

enum CursorIdentityDecoder {
    static func decode(_ data: Data) throws -> CursorRemoteIdentity {
        let response: GetMeResponse
        do {
            response = try JSONDecoder().decode(GetMeResponse.self, from: data)
        } catch {
            throw CursorSpikeError.invalidResponse
        }
        guard let userID = string(from: response.userID),
              !userID.isEmpty,
              !response.authID.isEmpty
        else {
            throw CursorSpikeError.invalidResponse
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
            authID: response.authID,
        )
    }

    private static func string(from value: StringOrNumber?) -> String? {
        switch value {
        case let .string(string):
            string
        case let .number(number):
            NSDecimalNumber(decimal: number).stringValue
        case nil:
            nil
        }
    }
}

private struct GetMeResponse: Decodable {
    let authID: String
    let email: String?
    let userID: StringOrNumber?
    let firstName: String?
    let lastName: String?
    let teamID: StringOrNumber?

    enum CodingKeys: String, CodingKey {
        case authID = "authId"
        case email
        case userID = "userId"
        case firstName
        case lastName
        case teamID = "teamId"
    }
}

private enum StringOrNumber: Decodable {
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
