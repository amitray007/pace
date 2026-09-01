# Technical architecture

## Decision

Build Pace as a native macOS application. Use SwiftUI for application views, AppKit for the
status item and windows, and Core Animation for the reference rail's precise and interruptible
motion.

This choice fits a Mac-only utility that needs non-activating windows, screen-edge placement,
Spaces and full-screen behavior, click-through hit testing, high frame-rate animation, launch at
login, and low idle overhead. Electron and Tauri add no product benefit for the first platform.

## System boundaries

```text
Provider processes and APIs
          │
          ▼
Provider adapters ──▶ snapshot normalizer ──▶ snapshot store
                                                │
                                  account usage status resolver
                                                │
                         ┌──────────────────────┼──────────────────────┐
                         ▼                      ▼                      ▼
                  menu-bar model         edge-rail model        settings model
                         │                      │                      │
                         ▼                      ▼                      ▼
                  status item/panel      NSPanel + CA layers     SwiftUI window
```

Provider adapters do not know about presentation. Views do not parse provider responses.

## Domain model

```swift
struct ProviderAccount: Identifiable, Sendable {
    let id: AccountID
    let providerID: ProviderID
    var displayName: String
    let planName: String?
    let identity: ProviderIdentity
    var isEnabled: Bool
}

struct LimitSnapshot: Identifiable, Sendable {
    let id: String
    let providerID: String
    let accountID: String
    let bucketID: String
    let label: String
    let usedFraction: Double
    let windowDuration: Duration?
    let resetsAt: Date?
    let observedAt: Date
    let freshness: Freshness
}
```

Bucket identity includes provider, account, quota subject when present, and provider-defined bucket
ID. This prevents values
from different identities from overwriting each other.

Snapshot `Freshness` records the state of returned data. `AccountUsageStatus` resolves those
snapshots together with the account connection state. It keeps data freshness separate from the
latest connection issue, so a failed refresh can retain and label the last good snapshots as stale.
A missing bucket is not a zero-percent snapshot.

## Provider interface

The current provider seam supports deterministic account discovery and per-account refresh. It
needs no provider process or harness to remain active.

Production adapters can add these capabilities after their feasibility spikes prove the required
lifecycle:

- discover configured accounts without exposing secrets;
- read an initial normalized snapshot;
- stream updates when the provider supports them;
- report authentication and freshness state;
- reconnect with bounded backoff;
- stop all processes and timers cleanly.

Each adapter declares which account and quota capabilities it supports. The app must not infer that
all providers expose the same window names or reset behavior.

## Provider feasibility

| Provider | Source | Confidence | Boundary |
| --- | --- | --- | --- |
| Codex | Supported local `codex app-server` JSON-RPC | High | Use `account/rateLimits/read` and `account/rateLimits/updated`. Keep each account in a separate `CODEX_HOME`. |
| Claude Code | Source-verified OAuth compatibility adapter | Medium-high | Bind an explicit `CLAUDE_CONFIG_DIR`, verify identity before usage, serialize reads, and rotate only through the same provider-owned source. |
| Cursor | Source-verified compatibility adapter | Medium-high | Bind the default Keychain account or an isolated Cursor Agent file profile, verify identity before usage, and keep refreshed access tokens in memory only. |
| Grok | Source-verified Grok Build compatibility adapter | Medium-high | Keep each account in a separate `GROK_HOME`; verify personal and team behavior separately. |
| GitHub Copilot | GitHub-authenticated usage adapter | Medium-high | Bind every credential to an explicit GitHub identity; never depend on whichever `gh` account happens to be active. |

Sources:

- [Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [OpenUsage Claude provider](https://github.com/robinebers/openusage/blob/main/docs/providers/claude.md)
- [OpenUsage Cursor provider](https://github.com/robinebers/openusage/blob/main/docs/providers/cursor.md)
- [Grok Build authentication](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md)
- [Cursor usage and limits](https://prod.cursor.com/help/models-and-usage/usage-limits)
- [Cursor CLI authentication](https://docs.cursor.com/en/cli/reference/authentication)

### Codex

Start `codex app-server --stdio`, perform the JSON-RPC initialization handshake, request
`account/rateLimits/read`, then listen for `account/rateLimits/updated`. Keep one background process
while Codex data is enabled. Reconnect with bounded backoff if it exits.

The production adapter foundation resolves the Codex executable without relying on an editor or
harness, replaces ambient `CODEX_HOME` with the selected explicit profile, requests `account/read`
without proactive token refresh, and rejects accounts that do not expose a verifiable ChatGPT
email. It renders all returned limit IDs and primary or secondary windows. The earlier bounded
request process is replaced by one persistent connection per explicit profile. Requests use
correlated IDs, asynchronous pipe I/O, and bounded timeouts. Sparse
`account/rateLimits/updated` notifications trigger a full read instead of clearing omitted fields;
one pending signal closes the read-before-subscribe race. Process exits mark last-good data stale,
then reconnect with bounded backoff. Shutdown closes stdin, waits briefly, and force-reaps a process
that ignores termination before a replacement starts.

The generic refresh coordinator applies streamed results to the same store read by both surfaces.
It reconciles one monitor per enabled account from committed store changes. Registration and
re-enablement start monitoring; disablement and removal cancel it. Store mutations serialize the
complete read-save-publish transaction so concurrent account updates cannot overwrite each other.
An applied delivery and a persistence failure are separate events, which lets both surfaces preserve
last-good state while showing a save error. Runtime replacement explicitly shuts down lifecycle
adapters before constructing their replacements, so a profile cannot retain an orphaned app-server
process.

The account coordinator is the presentation-facing boundary for onboarding and account lifecycle.
Discovery runs only after an explicit user action and does not mutate Pace state. It classifies
each verified result as available, already registered, bound to a different identity, or already
known through another credential source. Adding one candidate rechecks those rules against current
state. A normalized real profile path, Keychain service/account pair, or explicit command-line
tool/account/configuration binding can belong to only one Pace account per provider; simulated
fixtures remain exempt. Command-line account keys compare the tool and account without case
sensitivity. Rename, enable, disable, per-account refresh, and removal all flow through the same
coordinator. Removal deletes normalized Pace state and never deletes provider-owned credentials or
profiles.

The production provider catalog derives one adapter per promoted provider from all registered real
credential bindings, including disabled accounts that may be re-enabled. The active runtime installs
that adapter only while the provider has an enabled real account. Refresh and update-monitor
reconciliation exclude retained simulated bindings from a provider's live adapter. Disabling or
removing the last enabled real account rebuilds the runtime with the simulated adapter and refreshes
the retained fixture before showing it again. The shared profile-onboarding flow stops the current
runtime, verifies only the selected profile, registers or re-enables that one account, performs an
initial refresh, and then rebuilds the shared runtime from every registered profile. A failed
initial refresh removes a new registration or restores the disabled state of an account that Pace
tried to re-enable. This transition occurs only after the explicit flow succeeds. Simulated
accounts for providers without production adapters remain unchanged.

The live spike was verified on 2026-08-31 with Codex CLI 0.151.0. The response contained a general
weekly bucket plus model-specific five-hour and weekly buckets. This proves the UI must render
returned buckets dynamically.

### Claude Code

The production Claude compatibility adapter reads explicit `CLAUDE_CONFIG_DIR` profiles without a
running Claude Code process. It also matches Claude Code's source-verified
`CLAUDE_SECURESTORAGE_CONFIG_DIR` precedence, Unicode-normalized Keychain service hash, and current
user Keychain account selector. Pace persists those non-secret selectors with the account so a
restart cannot bind a profile to a different credential. It reads only the selected Keychain item
or owner-private `.credentials.json`, requires `user:profile`, verifies `/api/oauth/profile`, and
only then reads `/api/oauth/usage`. It rejects redirects, bounds response size and request time, and
serializes all Claude reads because the usage endpoint rate-limits aggressive polling.

When an access token is near expiry, a registered account verifies its current identity before any
refresh or credential write. Pace then holds the same current and legacy OAuth refresh locks used
by Claude Code 2.1.252, reloads the selected credential, and adopts a sibling rotation when one has
already completed. Its final refresh-token comparison and write run under Claude Code's
`.storage-write.lock`. File writes preserve unknown credential fields, use an owner-only atomic
replacement, and reject symbolic links or group-readable files. Keychain writes target the exact
service and account that supplied the credential. Pace re-verifies identity after every rotation
before retrying usage. If the provider accepts a rotated refresh token but the local write then
fails, Pace reports sign-in required. It does not claim that the old refresh token is still valid.

The default profile read-only smoke passed on 2026-09-01 with Claude Code 2.1.252 and no running
Claude process. Deterministic production tests cover two profiles, persisted secure-storage
selectors, serialized and cancellable requests, source fallback, scope rejection, identity checks
before and after rotation, current and legacy OAuth lock ownership, storage-write contention,
refresh-token comparison, write failure, missing buckets, and polling backoff. A second distinct
live account, live Keychain and file rotation, and Team or Enterprise response variants remain
external validation checks.

### Cursor

The production Cursor compatibility adapter supports two credential bindings. The default binding
reads the exact Cursor Agent Keychain services without allowing an authentication prompt.
Additional accounts use an explicit home directory and Cursor Agent's owner-private file credential
store. Cursor Agent owns login, logout, and durable credential rotation. Pace stores only the home
path, credential-source kind, profile ownership, and verified identity. Existing path-only Cursor
bindings migrate by treating the current macOS home as Keychain-backed and other homes as
file-backed.

For every refresh, the adapter reads the selected profile only, matches the access-token JWT subject
to `authInfo.authId` in that profile's CLI config, then calls Cursor's
`DashboardService/GetMe`. It requires the server response to return the same authentication ID and
checks the returned user and team against the registered Pace identity. Only then does it call
`DashboardService/GetCurrentPeriodUsage`; `GetPlanInfo` is optional and cannot discard valid usage.
No Cursor process or coding harness must remain running. Expired access tokens can be refreshed
through Cursor's source-verified OAuth endpoint. The refreshed access token stays in process memory;
Pace never changes the provider-owned Keychain or file. The adapter reloads that source after each
read and restarts once if Cursor Agent changed it concurrently. Requests serialize per credential
source, so overlapping reads for one account cannot race while a slow account does not block other
Cursor profiles.

The production default-profile smoke passed on 2026-09-01 with Cursor Agent
2026.07.01-41b2de7 and no running Cursor application or agent process. Deterministic tests cover
two isolated profiles, Keychain and private-file ownership, signed-out and partial failures,
identity checks before usage and after refresh, in-memory refresh reuse, concurrent source change,
cancellation, response-size boundaries, dynamic and empty buckets, conservative polling, and
provider backoff. Two distinct
live file profiles, live provider-owned credential rotation, and Enterprise response variants
remain external validation checks. The adapter never reads Cursor Desktop SQLite state or browser
cookies.

### Grok

The production Grok adapter reads explicit `GROK_HOME` profiles without starting Grok. It accepts
only one owner-private first-party xAI OIDC session from the selected `auth.json`; API keys, custom
issuers, ambiguous credentials, expired sessions, group-readable files, and symbolic-link
credential files are rejected before network use.

Every discovery and refresh calls the Grok CLI proxy `/user?include=subscription` first. Refresh
compares the canonical remote user, principal, and team identity with the registered Pace identity
before calling `/billing?format=credits`. Weekly, monthly, legacy included-credit, and capped
pay-as-you-go values normalize into provider-owned quota buckets. A mismatch becomes the shared
identity-mismatch state without requesting billing or replacing last-good data.

Enabled accounts poll independently at a 15-minute baseline. Rate-limit retry times extend that
delay; authentication and identity failures use a slower retry interval. Disabling or removing the
account cancels its polling task. The read-only live smoke passed on 2026-09-01 using the existing
private default profile without a running Grok process. Two distinct live profiles, credential
rotation, and additional personal or team response shapes remain external validation checks.

### GitHub Copilot

The production GitHub Copilot adapter uses GitHub CLI as the credential owner and account selector,
not as a usage harness. Account discovery uses GitHub CLI's documented JSON status output. Token
loading always supplies `--hostname github.com --user <login>`, removes ambient token variables,
disables prompts, and applies a hard process timeout. Pace stores the selected login, optional
GitHub CLI configuration directory, and verified numeric GitHub user identity. It never stores the
token.

Every discovery and refresh verifies the selected token through GitHub's documented `GET /user`
API before quota access. Refresh then calls `GET /copilot_internal/user`, which is used by official
Copilot clients and allowed by GitHub's documented network policy but is not a public REST
contract. Its code and failure behavior therefore remain isolated as a compatibility adapter.
Redirects are refused, responses are size and time bounded, and one account's failure does not hide
another account.

Credits, Chat, Completions, and legacy Free counts normalize without averaging accounts.
Organization-managed seats may honestly produce no percentage bucket when GitHub returns no
per-user denominator. Pace does not present amount-only spend or overage counters as quota limits.
Enabled accounts poll at a 15-minute baseline. Authentication and identity failures back off for
one hour; other failures back off for 30 minutes; provider retry times are honored. The read-only
live smoke passed on 2026-09-01 with the existing GitHub CLI account and no editor, Copilot CLI, or
coding harness. Two distinct live accounts, credential rotation, and live Free, Business, and
Enterprise variants remain external checks.

### Compatibility adapters

An undocumented endpoint is allowed only behind a provider-specific adapter whose source and
behavior have been reviewed. The adapter must verify the remote identity before publishing data,
use conservative polling and bounded backoff, preserve a last-good snapshot, and fail only the
affected account. Popularity is supporting evidence, not provider authorization.

Provider CLIs own credentials when they offer isolated profiles. Pace stores a non-secret profile
reference and expected identity. The CLI is needed for login or reauthentication, not for ongoing
usage display.

### Multiple accounts

A logical adapter belongs to one provider. Every discovery and refresh operation uses an explicit
account and credential binding, so one adapter can refresh several isolated provider profiles
without depending on ambient login state. If a provider only exposes the currently authenticated
CLI account, the first version must say so instead of pretending to support parallel accounts.

Multiple-account credential handling remains provider-specific. Optional provider-issued API
credentials belong in Keychain. Existing CLI OAuth tokens remain owned by the provider CLI or an
isolated provider profile. Pace never silently converts an ambient login into a Pace-owned token.

## Presentation architecture

### Menu bar

`NSStatusItem` owns the status icon. A semitransient `NSPopover` hosts the SwiftUI menu panel and
keeps provider and account selection open during internal interaction. Its model derives provider
tabs, account selection, quota rows, and the headline value from the shared snapshot store.

### Edge rail

`EdgePanelController` owns a borderless, non-activating `NSPanel`. It follows the selected display's
visible frame and observes display, Space, full-screen, Stage Manager, menu-bar, and Dock changes.

The collapsed panel ignores pointer events. Activation logic arms it only after a configured intent
condition. Visible-shape hit testing prevents transparent window regions from blocking the
application below.

Core Animation layers own the rail path, connector, progress rings, and reference-critical motion.
SwiftUI hosts provider content and settings where layout convenience does not weaken animation or
hit-testing control.

## Persistence and security

- Store normalized snapshots and preferences in Application Support.
- Persist the simulated shell to `state.json` and presentation choices to `preferences.json`; both
  files use owner-only permissions and contain no provider secrets.
- Store optional provider-issued credentials in Keychain.
- Never store conversation text, prompts, browser cookies, or silently copied OAuth tokens.
- Record provider, account, bucket, source, observation time, and error state.
- Keep polling local where possible and use provider-safe intervals.
- Keep notification evaluation local and opt-in.
- Redact account identifiers from diagnostics unless the user explicitly exports them.

## Unresolved implementation checks

- Verify modifier-hover activation, click-through behavior, and suppression on physical hardware
  with overlay scrollbars, pointer drags, full-screen applications, Spaces, and multiple displays.
- Select the oldest supported macOS version after the visual prototype proves required APIs.
- Verify multi-account capabilities independently for every provider.
- Verify two live Claude config directories plus live Keychain and file rotation without account
  crossover.
- Verify two live Cursor Agent file profiles and live CLI-owned credential rotation without account
  crossover.
- Measure reference paths, timings, and colors from the source media during the visual phase.
