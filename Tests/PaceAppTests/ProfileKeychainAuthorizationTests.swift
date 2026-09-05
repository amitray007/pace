import Foundation
@testable import PaceApp
import PaceCore
import PaceProviders
import Testing

@MainActor
@Suite("Profile keychain authorization", .serialized)
struct ProfileKeychainAuthorizationTests {
    @Test func `claude authorization retains the supplied credential binding`() {
        let directory = URL(filePath: "/tmp/pace-claude-profile", directoryHint: .isDirectory)
        let profile = ClaudeProfile(
            directory: directory,
            ownership: .existing,
            secureStorageDirectory: URL(filePath: "/tmp/pace-secure", directoryHint: .isDirectory),
            keychainService: "custom-service",
            keychainAccount: "custom-account",
        )
        let request = ProfileKeychainAuthorization(
            error: ProviderFailure.unavailable(code: "claude-credential-needs-authorization"),
            providerID: .claude,
            directory: directory,
            claudeProfile: profile,
        )

        #expect(request == .claude(profile))
        #expect(request?.providerID == .claude)
    }

    @Test func `cursor authorization retains the supplied isolated profile`() {
        let directory = URL(filePath: "/tmp/pace-cursor-profile", directoryHint: .isDirectory)
        let profile = CursorProfile(
            homeDirectory: directory,
            credentialSource: .isolatedFile,
            ownership: .existing,
            displayName: "Custom Cursor",
        )
        let request = ProfileKeychainAuthorization(
            error: ProviderFailure.unavailable(code: "cursor-credential-needs-authorization"),
            providerID: .cursor,
            directory: directory,
            cursorProfile: profile,
        )

        #expect(request == .cursor(profile))
        #expect(request?.providerID == .cursor)
    }

    @Test func `only matching provider authorization failures request a retry`() {
        let directory = URL(filePath: "/tmp/pace-profile", directoryHint: .isDirectory)
        #expect(ProfileKeychainAuthorization(
            error: ProviderFailure.failed(code: "network"), providerID: .claude,
            directory: directory,
        ) == nil)
        #expect(ProfileKeychainAuthorization(
            error: ProviderFailure.unavailable(code: "cursor-credential-needs-authorization"),
            providerID: .claude, directory: directory,
        ) == nil)
        #expect(ProfileKeychainAuthorization(
            error: ProviderFailure.unavailable(code: "claude-credential-needs-authorization"),
            providerID: .cursor, directory: directory,
        ) == nil)
        #expect(ProfileKeychainAuthorization(
            error: ProviderFailure.unavailable(code: "claude-credential-needs-authorization"),
            providerID: .codex, directory: directory,
        ) == nil)
    }

    @Test func `onboarding prompts require the explicit retry and close after failure`(
    ) async throws {
        struct Failure: Error {}
        KeychainInteractionPolicy.disableAutomaticPrompts()
        try await PacePresentationModel.performProfileOnboarding(allowsPrompts: false) {
            #expect(!KeychainInteractionPolicy.promptsAreAllowed)
        }
        await #expect(throws: Failure.self) {
            try await PacePresentationModel.performProfileOnboarding(allowsPrompts: true) {
                #expect(KeychainInteractionPolicy.promptsAreAllowed)
                throw Failure()
            }
        }
        #expect(!KeychainInteractionPolicy.promptsAreAllowed)
    }
}
