import Foundation
import PaceCore
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension CursorUsageReader {
    func connectRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        return request
    }

    func refreshRequest(_ refreshToken: String) -> URLRequest {
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
        ])
        return request
    }

    func send(_ request: URLRequest) async throws(CursorProviderError) -> CursorHTTPResponse {
        do {
            let response = try await transport.send(request)
            guard response.body.count <= CursorURLSessionTransport.maximumResponseSize else {
                throw CursorProviderError.invalidResponse
            }
            return response
        } catch let error as CursorProviderError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transportFailed
        }
    }

    func requireSuccess(_ response: CursorHTTPResponse) throws(CursorProviderError) {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401, 403:
            throw .reauthenticationRequired
        case 429:
            throw .rateLimited(retryAfter: retryAfter(from: response))
        default:
            throw .requestFailed(statusCode: response.statusCode)
        }
    }

    func retryAfter(from response: CursorHTTPResponse) -> TimeInterval? {
        guard let value = response.header("retry-after")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now())) }
    }

    func decodeRefreshedAccessToken(_ data: Data) throws(CursorProviderError) -> String {
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw CursorProviderError.invalidResponse
            }
            object = decoded
        } catch let error as CursorProviderError {
            throw error
        } catch {
            throw .invalidResponse
        }
        if object["shouldLogout"] as? Bool == true {
            throw .reauthenticationRequired
        }
        let accessToken = (object["access_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let accessToken, !accessToken.isEmpty else {
            throw .invalidResponse
        }
        return accessToken
    }

    func verify(
        _ remote: CursorRemoteIdentity,
        credential: CursorCredential,
        expected: ProviderIdentity?,
    ) throws(CursorProviderError) {
        guard remote.authenticationID.caseInsensitiveCompare(credential.authenticationID)
            == .orderedSame
        else {
            throw .invalidCredential
        }
        guard let expected else {
            return
        }
        guard remote.identity.providerIdentity.subjectID == expected.subjectID,
              remote.identity.providerIdentity.organizationID == expected.organizationID
        else {
            throw .identityMismatch
        }
    }

    func validate(
        _ accessToken: String,
        authenticationID: String,
    ) throws(CursorProviderError) {
        guard let subject = jwtPayload(accessToken)?["sub"] as? String,
              subject.caseInsensitiveCompare(authenticationID) == .orderedSame
        else {
            throw .invalidCredential
        }
    }

    func needsRefresh(_ accessToken: String) -> Bool {
        guard let expiration = tokenExpiration(accessToken) else {
            return true
        }
        return expiration.timeIntervalSince(now()) <= 300
    }

    func isExpired(_ accessToken: String) -> Bool {
        guard let expiration = tokenExpiration(accessToken) else {
            return true
        }
        return expiration <= now()
    }

    private func tokenExpiration(_ accessToken: String) -> Date? {
        guard let value = jwtPayload(accessToken)?["exp"] as? NSNumber else {
            return nil
        }
        let seconds = value.doubleValue
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return nil
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload.append(String(repeating: "=", count: (4 - payload.count % 4) % 4))
        guard let data = Data(base64Encoded: payload) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
