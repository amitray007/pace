import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Keychain interaction policy", .serialized)
struct KeychainInteractionPolicyTests {
    @Test
    func `prompts are allowed only inside the window`() async throws {
        KeychainInteractionPolicy.disableAutomaticPrompts()
        #expect(!KeychainInteractionPolicy.promptsAreAllowed)

        let allowedInside = try await KeychainInteractionPolicy.allowingPrompts {
            KeychainInteractionPolicy.promptsAreAllowed
        }

        #expect(allowedInside)
        #expect(!KeychainInteractionPolicy.promptsAreAllowed)
    }

    @Test
    func `a failing body still closes the window`() async {
        struct Failure: Error {}
        KeychainInteractionPolicy.disableAutomaticPrompts()

        await #expect(throws: Failure.self) {
            try await KeychainInteractionPolicy.allowingPrompts {
                throw Failure()
            }
        }

        #expect(!KeychainInteractionPolicy.promptsAreAllowed)
    }

    @Test
    func `windows do not overlap`() async throws {
        // Two user actions must not interleave: the second window opens only
        // after the first has closed, so the flag never stays raised for a
        // read that lands between them.
        KeychainInteractionPolicy.disableAutomaticPrompts()
        let firstEntered = AsyncSignal()
        let firstMayFinish = AsyncSignal()
        let secondEntered = AsyncSignal()

        let first = Task {
            try await KeychainInteractionPolicy.allowingPrompts {
                await firstEntered.signal()
                await firstMayFinish.wait()
            }
        }
        await firstEntered.wait()

        let second = Task {
            try await KeychainInteractionPolicy.allowingPrompts {
                await secondEntered.signal()
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await !secondEntered.isSignalled)

        await firstMayFinish.signal()
        try await first.value
        try await second.value
        #expect(await secondEntered.isSignalled)
        #expect(!KeychainInteractionPolicy.promptsAreAllowed)
    }

    @Test
    func `only the authorization codes ask for a prompted read`() {
        #expect(KeychainInteractionPolicy.needsAuthorization(
            .unavailable(code: "claude-credential-needs-authorization"),
        ))
        #expect(KeychainInteractionPolicy.needsAuthorization(
            .unavailable(code: "cursor-credential-needs-authorization"),
        ))
        #expect(!KeychainInteractionPolicy.needsAuthorization(
            .unavailable(code: "cursor-credential-unavailable"),
        ))
        #expect(!KeychainInteractionPolicy.needsAuthorization(.needsAuthentication))
        #expect(!KeychainInteractionPolicy.needsAuthorization(nil))
    }
}

/// A one-shot signal that later waiters observe immediately.
private actor AsyncSignal {
    private(set) var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async {
        guard !isSignalled else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
