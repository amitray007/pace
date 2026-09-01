import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Cursor usage reader")
struct CursorUsageReaderTests {
    @Test
    func `verifies CLI and remote identity before requesting usage`() async throws {
        let profile = CursorTestSupport.profile(
            expectedIdentity: CursorTestSupport.identity().providerIdentity,
        )
        let loader = CursorStubCredentialLoader(
            profile: profile,
            credential: CursorTestSupport.credential(),
        )
        let transport = CursorStubTransport { request in
            switch request.url?.path {
            case "/aiserver.v1.DashboardService/GetMe":
                CursorTestSupport.identityResponse()
            case "/aiserver.v1.DashboardService/GetCurrentPeriodUsage":
                CursorTestSupport.usageResponse()
            default:
                CursorTestSupport.planResponse()
            }
        }
        let reader = makeReader(loader: loader, transport: transport)

        let result = try await reader.read(profile: profile, includeUsage: true)

        #expect(result.identity.providerIdentity == CursorTestSupport.identity().providerIdentity)
        #expect(result.metrics.count == 3)
        #expect(result.planName == "Team")
        #expect(await transport.requests.map(\.url?.path) == [
            "/aiserver.v1.DashboardService/GetMe",
            "/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            "/aiserver.v1.DashboardService/GetPlanInfo",
        ])
    }

    @Test
    func `refreshes into memory and reuses the cached token without writing provider state`(
    ) async throws {
        let profile = CursorTestSupport.profile()
        let expiring = CursorTestSupport.credential(
            expiresAt: CursorTestSupport.observedAt.addingTimeInterval(60),
        )
        let loader = CursorStubCredentialLoader(profile: profile, credential: expiring)
        let refreshedToken = CursorTestSupport.token(
            subject: expiring.authenticationID,
            expiresAt: CursorTestSupport.observedAt.addingTimeInterval(7200),
        )
        let transport = CursorStubTransport { request in
            switch request.url?.path {
            case "/oauth/token":
                CursorHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"access_token":"\#(refreshedToken)"}"#.utf8),
                )
            case "/aiserver.v1.DashboardService/GetMe":
                CursorTestSupport.identityResponse()
            default:
                CursorTestSupport.planResponse()
            }
        }
        let reader = makeReader(loader: loader, transport: transport)

        _ = try await reader.read(profile: profile, includeUsage: false)
        _ = try await reader.read(profile: profile, includeUsage: false)

        let requests = await transport.requests
        #expect(requests.filter { $0.url?.path == "/oauth/token" }.count == 1)
        #expect(requests.filter { $0.cursorBearerToken == refreshedToken }.count == 4)
    }

    @Test
    func `refreshes and retries when initial identity authentication fails`() async throws {
        let profile = CursorTestSupport.profile()
        let credential = CursorTestSupport.credential()
        let loader = CursorStubCredentialLoader(profile: profile, credential: credential)
        let refreshedToken = CursorTestSupport.token(
            subject: credential.authenticationID,
            expiresAt: CursorTestSupport.observedAt.addingTimeInterval(7200),
        )
        let transport = CursorStubTransport { request in
            switch (request.url?.path, request.cursorBearerToken) {
            case ("/aiserver.v1.DashboardService/GetMe", credential.accessToken):
                CursorHTTPResponse(statusCode: 401, body: Data())
            case ("/oauth/token", _):
                CursorHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"access_token":"\#(refreshedToken)"}"#.utf8),
                )
            case ("/aiserver.v1.DashboardService/GetMe", refreshedToken):
                CursorTestSupport.identityResponse()
            default:
                CursorTestSupport.planResponse()
            }
        }
        let reader = makeReader(loader: loader, transport: transport)

        let result = try await reader.read(profile: profile, includeUsage: false)

        #expect(result.identity.providerIdentity == CursorTestSupport.identity().providerIdentity)
        #expect(await transport.requests.map(\.url?.path) == [
            "/aiserver.v1.DashboardService/GetMe",
            "/oauth/token",
            "/aiserver.v1.DashboardService/GetMe",
            "/aiserver.v1.DashboardService/GetPlanInfo",
        ])
        #expect(await transport.requests.suffix(2).allSatisfy {
            $0.cursorBearerToken == refreshedToken
        })
    }

    @Test
    func `reverifies identity after usage authentication refresh`() async {
        let expected = CursorTestSupport.identity().providerIdentity
        let profile = CursorTestSupport.profile(expectedIdentity: expected)
        let credential = CursorTestSupport.credential()
        let loader = CursorStubCredentialLoader(profile: profile, credential: credential)
        let refreshedToken = CursorTestSupport.token(
            subject: credential.authenticationID,
            expiresAt: CursorTestSupport.observedAt.addingTimeInterval(7200),
        )
        let transport = CursorStubTransport { request in
            switch (request.url?.path, request.cursorBearerToken) {
            case ("/aiserver.v1.DashboardService/GetMe", credential.accessToken):
                CursorTestSupport.identityResponse()
            case ("/aiserver.v1.DashboardService/GetCurrentPeriodUsage", credential.accessToken):
                CursorHTTPResponse(statusCode: 401, body: Data())
            case ("/oauth/token", _):
                CursorHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"access_token":"\#(refreshedToken)"}"#.utf8),
                )
            case ("/aiserver.v1.DashboardService/GetMe", refreshedToken):
                CursorTestSupport.identityResponse(userID: "other-user")
            default:
                CursorTestSupport.usageResponse()
            }
        }
        let reader = makeReader(loader: loader, transport: transport)

        await #expect(throws: CursorProviderError.identityMismatch) {
            try await reader.read(profile: profile, includeUsage: true)
        }
        #expect(await transport.requests.map(\.url?.path) == [
            "/aiserver.v1.DashboardService/GetMe",
            "/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            "/oauth/token",
            "/aiserver.v1.DashboardService/GetMe",
        ])
    }

    @Test
    func `rejects a token subject mismatch before making a request`() async {
        let profile = CursorTestSupport.profile()
        let credential = CursorTestSupport.credential(
            accessToken: CursorTestSupport.token(
                subject: "auth0|other",
                expiresAt: CursorTestSupport.observedAt.addingTimeInterval(3600),
            ),
        )
        let loader = CursorStubCredentialLoader(profile: profile, credential: credential)
        let transport = CursorStubTransport { _ in CursorTestSupport.identityResponse() }

        await #expect(throws: CursorProviderError.invalidCredential) {
            try await makeReader(loader: loader, transport: transport).read(
                profile: profile,
                includeUsage: true,
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `rejects a remote authentication mismatch before requesting usage`() async {
        let profile = CursorTestSupport.profile()
        let credential = CursorTestSupport.credential()
        let loader = CursorStubCredentialLoader(profile: profile, credential: credential)
        let transport = CursorStubTransport { _ in
            CursorTestSupport.identityResponse(authenticationID: "auth0|other")
        }

        await #expect(throws: CursorProviderError.invalidCredential) {
            try await makeReader(loader: loader, transport: transport).read(
                profile: profile,
                includeUsage: true,
            )
        }
        #expect(await transport.requests.map(\.url?.path) == [
            "/aiserver.v1.DashboardService/GetMe",
        ])
    }

    @Test
    func `restarts once when the selected profile changes during a read`() async throws {
        let profile = CursorTestSupport.profile()
        let first = CursorTestSupport.credential(authenticationID: "auth0|first")
        let second = CursorTestSupport.credential(authenticationID: "auth0|second")
        let loader = CursorStubCredentialLoader(resultsByPath: [
            profile.homeDirectory.path: [.success(first), .success(second), .success(second)],
        ])
        let transport = CursorStubTransport { request in
            let secondIdentity = request.cursorBearerToken == second.accessToken
            return CursorTestSupport.identityResponse(
                userID: secondIdentity ? "second" : "first",
                teamID: nil,
                authenticationID: secondIdentity ? second.authenticationID : first.authenticationID,
            )
        }
        let reader = makeReader(loader: loader, transport: transport)

        let result = try await reader.read(profile: profile, includeUsage: false)

        #expect(result.identity.userID == "second")
        #expect(await transport.requests.filter {
            $0.url?.path == "/aiserver.v1.DashboardService/GetMe"
        }.count == 2)
    }

    @Test
    func `serializes one source and releases a cancelled waiter`() async throws {
        let gate = CursorRequestGate()
        try await gate.acquire()
        let waiter = Task { try await gate.acquire() }
        try await Task.sleep(for: .milliseconds(10))
        waiter.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        try await gate.acquire()
        await gate.release()
    }

    @Test
    func `uses one request gate per credential source`() async {
        let pool = CursorRequestGatePool()
        let keychain = CursorTestSupport.profile("personal", source: .defaultKeychain)
        let isolated = CursorTestSupport.profile("personal", source: .isolatedFile)

        let firstKeychainGate = await pool.gate(for: keychain)
        let secondKeychainGate = await pool.gate(for: keychain)
        let isolatedGate = await pool.gate(for: isolated)

        #expect(firstKeychainGate === secondKeychainGate)
        #expect(firstKeychainGate !== isolatedGate)
    }

    @Test
    func `preserves provider retry interval without attempting refresh`() async {
        let profile = CursorTestSupport.profile()
        let credential = CursorTestSupport.credential()
        let loader = CursorStubCredentialLoader(profile: profile, credential: credential)
        let transport = CursorStubTransport { _ in
            CursorHTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "120"],
                body: Data(),
            )
        }
        let reader = makeReader(loader: loader, transport: transport)

        await #expect(throws: CursorProviderError.rateLimited(retryAfter: 120)) {
            try await reader.read(profile: profile, includeUsage: true)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `transport accepts a response at the exact size bound`() async throws {
        let bytes = byteStream("1234")

        let data = try await CursorURLSessionTransport.boundedData(
            from: bytes,
            maximumSize: 4,
        )

        #expect(data == Data("1234".utf8))
    }

    @Test
    func `transport rejects the first byte over the size bound`() async {
        let bytes = byteStream("12345")

        await #expect(throws: CursorProviderError.invalidResponse) {
            _ = try await CursorURLSessionTransport.boundedData(
                from: bytes,
                maximumSize: 4,
            )
        }
    }

    private func byteStream(_ value: String) -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            for byte in Data(value.utf8) {
                continuation.yield(byte)
            }
            continuation.finish()
        }
    }

    private func makeReader(
        loader: CursorStubCredentialLoader,
        transport: CursorStubTransport,
    ) -> CursorUsageReader {
        CursorUsageReader(
            credentialLoader: loader,
            transport: transport,
            gatePool: CursorRequestGatePool(),
            tokenCache: CursorAccessTokenCache(),
            now: { CursorTestSupport.observedAt },
        )
    }
}
