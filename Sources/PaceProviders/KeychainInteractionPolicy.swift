import Foundation
import PaceCore
import Security

/// When macOS may ask the user before Pace reads a credential from the keychain.
///
/// Pace reads keychain items that Claude Code and Cursor own. Those items live
/// in the login keychain, the file-based keychain that predates data
/// protection, and that keychain is authorised differently from the data
/// protection keychain that `SecItem` documentation mostly describes:
///
/// - `kSecUseAuthenticationUI` and `kSecUseNoAuthenticationUI` apply only to
///   the data protection keychain. `SecItem.h` says so for the latter:
///   "Legacy keychain items will still activate UI if needed". The legacy
///   implementation never reads either key, so passing them changed nothing,
///   and the password dialog kept appearing for every read.
/// - The login keychain honours `SecKeychainSetUserInteractionAllowed`. While
///   it is false a read carries no prompt credential, `securityd` evaluates the
///   item's access control without asking, and a read that Pace is not
///   admitted to fails with `errSecAuthFailed` or `errSecInteractionNotAllowed`
///   instead of raising the dialog.
///
/// Whether Pace is admitted depends on two lists `securityd` keeps on each
/// item. The application list is keyed by the reader's designated requirement,
/// which a certificate keeps stable across builds. The partition list is keyed
/// by a partition ID, and only a certificate issued by Apple (Developer ID, Mac
/// App Store, or Mac Development) earns a `teamid:` partition ID. Every other
/// signature, including a local self-signed certificate and the ad-hoc
/// signature a Homebrew install carries, is classified as `cdhash:` followed by
/// the binary's own code directory hash. "Always Allow" records that partition
/// ID, so for a build without a Developer ID the approval holds for that exact
/// binary and the next Pace build needs a new approval for each item. No
/// application-side change alters that classification.
///
/// The policy that follows from this is that no background read may raise the
/// dialog. A launch, an automatic refresh, or a manual refresh reports that
/// keychain access is needed, and only an action the user chose runs a read
/// with prompts allowed. The dialogs then appear once, together, at a moment
/// the user picked, and "Always Allow" holds for the installed build.
public enum KeychainInteractionPolicy {
    /// Failure codes that mean macOS refused a keychain read without asking.
    ///
    /// These are the codes the provider adapters report when every read
    /// returned `errSecAuthFailed` or `errSecInteractionNotAllowed` under this
    /// policy. They are the only failures that `allowingPrompts` can resolve.
    public static let authorizationRequiredCodes: Set<String> = [
        "claude-credential-needs-authorization",
        "cursor-credential-needs-authorization",
    ]

    /// Whether an account's connection issue is one that a prompted read fixes.
    public static func needsAuthorization(_ issue: AccountConnectionIssue?) -> Bool {
        guard case let .unavailable(code)? = issue else {
            return false
        }
        return authorizationRequiredCodes.contains(code)
    }

    /// Stops every keychain read in this process from showing the macOS
    /// dialog until `allowingPrompts` runs.
    ///
    /// Call once at launch, before the first provider read. The setting is
    /// process-wide, which is what Pace wants: it reads credentials other
    /// applications own and has a reported failure state for every read.
    public static func disableAutomaticPrompts() {
        setInteractionAllowed(false)
    }

    /// Whether a read may currently raise the macOS keychain dialog.
    public static var promptsAreAllowed: Bool {
        var allowed = DarwinBoolean(false)
        guard readInteractionAllowed(&allowed) == errSecSuccess else {
            return true
        }
        return allowed.boolValue
    }

    /// Runs `body` with the keychain dialog allowed, then restores the
    /// previous setting.
    ///
    /// Calls are serialised so two user actions cannot interleave their
    /// windows and leave prompts enabled for a background read that happens to
    /// land between them.
    public static func allowingPrompts<T: Sendable>(
        _ body: @Sendable () async throws -> T,
    ) async throws -> T {
        await gate.acquire()
        let previous = promptsAreAllowed
        setInteractionAllowed(true)
        do {
            let value = try await body()
            setInteractionAllowed(previous)
            await gate.release()
            return value
        } catch {
            setInteractionAllowed(previous)
            await gate.release()
            throw error
        }
    }

    private static let gate = KeychainInteractionGate()

    /// `SecKeychainSetUserInteractionAllowed` is marked deprecated together
    /// with the rest of the file-based keychain API, but it remains the only
    /// switch that governs prompts for items in that keychain, which is where
    /// Claude Code and Cursor store the credentials Pace reads. This and the
    /// getter below are the whole of Pace's dependency on it.
    private static func setInteractionAllowed(_ allowed: Bool) {
        _ = SecKeychainSetUserInteractionAllowed(allowed)
    }

    private static func readInteractionAllowed(_ allowed: inout DarwinBoolean) -> OSStatus {
        SecKeychainGetUserInteractionAllowed(&allowed)
    }
}

/// A non-reentrant lock for `allowingPrompts`.
///
/// An actor alone is not enough: awaiting the body inside an actor method lets
/// a second caller enter, so the hold is tracked explicitly and later callers
/// wait on a continuation until the holder releases it.
private actor KeychainInteractionGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().resume()
    }
}
