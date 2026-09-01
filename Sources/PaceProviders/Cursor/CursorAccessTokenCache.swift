import Foundation
import PaceCore

actor CursorAccessTokenCache {
    static let shared = CursorAccessTokenCache()

    private var entries: [CursorProfileKey: CursorAccessTokenCacheEntry] = [:]

    func accessToken(
        for profile: CursorProfile,
        credential: CursorCredential,
    ) -> String? {
        let key = CursorProfileKey(profile: profile)
        guard let entry = entries[key], entry.matches(credential) else {
            entries.removeValue(forKey: key)
            return credential.accessToken
        }
        return entry.refreshedAccessToken
    }

    func store(
        _ accessToken: String,
        for profile: CursorProfile,
        credential: CursorCredential,
    ) {
        entries[CursorProfileKey(profile: profile)] = CursorAccessTokenCacheEntry(
            sourceAccessToken: credential.accessToken,
            sourceRefreshToken: credential.refreshToken,
            refreshedAccessToken: accessToken,
        )
    }
}

struct CursorProfileKey: Hashable {
    let path: String
    let source: CursorCredentialSource

    init(profile: CursorProfile) {
        path = profile.homeDirectory.path
        source = profile.credentialSource
    }
}

private struct CursorAccessTokenCacheEntry {
    let sourceAccessToken: String?
    let sourceRefreshToken: String?
    let refreshedAccessToken: String

    func matches(_ credential: CursorCredential) -> Bool {
        sourceAccessToken == credential.accessToken
            && sourceRefreshToken == credential.refreshToken
    }
}
