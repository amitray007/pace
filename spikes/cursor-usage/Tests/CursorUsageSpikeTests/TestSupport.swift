import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import CursorUsageSpikeCore

enum CursorSpikeTestSupport {
    static let referenceDate = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        _ name: String = "default",
        expectedIdentity: CursorIdentity? = nil,
    ) -> CursorProfileBinding {
        CursorProfileBinding.isolated(
            homeDirectory: URL(filePath: "/profiles/\(name)", directoryHint: .isDirectory),
            expectedIdentity: expectedIdentity,
        )
    }

    static func identity(
        userID: String = "user-a",
        teamID: String? = "team-a",
    ) -> CursorIdentity {
        CursorIdentity(userID: userID, teamID: teamID)
    }

    static func token(userID: String = "user-a") -> String {
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payload = base64URL(Data("{\"sub\":\"auth0|\(userID)\"}".utf8))
        return "\(header).\(payload).signature"
    }

    static func usageResponse(percent: Double = 25) -> CursorHTTPResponse {
        CursorHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "enabled": true,
                  "billingCycleStart": 1788134400000,
                  "billingCycleEnd": 1790812800000,
                  "planUsage": {
                    "totalPercentUsed": \(percent),
                    "autoPercentUsed": 10,
                    "apiPercentUsed": 15
                  }
                }
                """.utf8,
            ),
        )
    }

    static func identityResponse(
        userID: String = "user-a",
        teamID: String? = "team-a",
        authID: String = "auth0|user-a",
    ) -> CursorHTTPResponse {
        let team = teamID.map { "\"teamId\": \"\($0)\"," } ?? ""
        return CursorHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "authId": "\(authID)",
                  "userId": "\(userID)",
                  \(team)
                  "email": "hidden@example.invalid"
                }
                """.utf8,
            ),
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct StubCredentialLoader: CursorCredentialLoading {
    let credentialsByPath: [String: CursorCredential]

    init(profile: CursorProfileBinding, credential: CursorCredential) {
        credentialsByPath = [profile.homeDirectory.path: credential]
    }

    init(credentialsByPath: [String: CursorCredential]) {
        self.credentialsByPath = credentialsByPath
    }

    func load(for profile: CursorProfileBinding) throws -> CursorCredential {
        guard let credential = credentialsByPath[profile.homeDirectory.path] else {
            throw CursorSpikeError.signedOut
        }
        return credential
    }
}

actor StubTransport: CursorHTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> CursorHTTPResponse

    private let handler: Handler
    private var recordedRequests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) throws -> CursorHTTPResponse {
        recordedRequests.append(request)
        return try handler(request)
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}

extension URLRequest {
    var bearerToken: String? {
        value(forHTTPHeaderField: "Authorization")?
            .replacingOccurrences(of: "Bearer ", with: "")
    }
}
