# Contributing to Pace

Thanks for looking. This file covers how the project is laid out, what the code is expected to do,
and what to run before you open a pull request.

## Getting set up

You need macOS 15 or later and Xcode with Swift 6.2.

```sh
git clone https://github.com/amitray007/pace
cd pace
make build
make test
```

`make install` builds a Release bundle, signs it with a local self-signed certificate, and installs
it to `/Applications`. The certificate is created on first run. It exists so your keychain
approvals survive rebuilds: an ad-hoc signature changes the code's identity every time, so macOS
would prompt on every launch.

## Layout

```
Sources/
  PaceCore/       State, persistence, quota model, refresh orchestration. No UI.
  PaceProviders/  One directory per provider. Credentials, transport, decoding.
  PaceApp/        SwiftUI views, AppKit windows, Core Animation for the rail.
```

The separation is load-bearing. `PaceCore` has no UI and no provider specifics, which is why most
of the test suite lives against it. A provider adapter normalizes whatever its API returns into the
shared snapshot model; nothing above `PaceProviders` knows what a Cursor response looks like.

## Rules the code follows

These come from `AGENTS.md` and are not negotiable in review:

**Never invent a number.** If a provider does not return a quota value or a reset time, show that
it is missing. An estimate that looks like data is worse than a blank.

**Never average across accounts.** Select an account, or show the most urgent quota. An average
hides the one that is about to run out.

**Render what the provider returns.** Do not assume every account exposes the same windows. Claude
reports a session and a weekly limit; Cursor reports something else entirely.

**Do not read browser cookies or copy OAuth tokens between tools.** Pace reads the credential each
provider's own CLI already stores, and nothing else. A compatibility adapter may call an
undocumented endpoint only if its source, identity checks, credential ownership, polling limits,
and failure behaviour are documented.

**Keep the collapsed edge rail click-through.** It must never intercept scrollbars, resize handles,
drags, scrolling, or trackpad momentum.

**Show the unhappy states.** Observation time, stale data, missing buckets, signed-out accounts,
and provider errors all need to be visible.

## Before you open a pull request

```sh
make check
```

That runs `format-check`, `lint`, `test`, and `build`. CI runs the same thing, so a green `make
check` locally means a green CI.

For anything that changes what you can see, also run the app and look at it:

```sh
make run
```

Screenshots or a short recording help a lot in the pull request, because visual regressions are
hard to catch in a diff.

## Tests

Tests use [Swift Testing](https://developer.apple.com/documentation/testing), not XCTest. Test
names are backtick-quoted sentences describing the behaviour:

```swift
@Test
func `a passed reset reads as imminent rather than negative`() {
```

Write the test that would have caught the bug. A comment explaining *why* the case matters is worth
more than one restating what the code does — several tests in this repo exist because a subtle
regression shipped once already, and the comment is what stops it coming back.

Provider work should be tested against recorded responses rather than the live API, so the suite
stays offline and deterministic.

## Style

`swiftformat` and `swiftlint` are enforced, and `make check` will fail on violations. Beyond that:

- Comments explain why, not what. If a line needs a comment to say what it does, rename something.
- Match the surrounding code's density and idiom.
- Keep files under the lint limits by extracting a real unit, not by shortening comments.

## Adding a provider

1. Create `Sources/PaceProviders/<Name>/` with an adapter, a credential loader, and a decoder.
2. Read credentials from where that provider's own tool already stores them. Do not invent a new
   credential store and do not prompt for a password.
3. Normalize the response into `LimitSnapshot` values. Report the windows the API actually
   returned.
4. Map every failure to an honest state: signed out, unavailable, stale, or an error with a code.
5. Add decoder tests using recorded response fixtures.
6. Document the endpoints, especially undocumented ones, in the provider directory.

## Reporting bugs

Open an issue with your macOS version, which providers are connected, and what you expected against
what you saw. Screenshots are welcome — turn on **Hide account addresses** in Settings first so you
do not publish your email.

For anything security-related, read [SECURITY.md](SECURITY.md) instead of opening a public issue.
